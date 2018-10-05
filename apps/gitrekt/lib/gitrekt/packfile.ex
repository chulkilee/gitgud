defmodule GitRekt.Packfile do
  @moduledoc """
  Conveniences for reading and writting Git pack files.
  """

  use Bitwise

  require Logger

  alias GitRekt.Git

  @type obj :: {Git.obj_type(), binary}
  @type obj_list :: [obj]

  @doc """
  Returns a *PACK* file for the given `oids` list.
  """
  @spec create(Git.repo(), [Git.oid() | {Git.oid(), boolean}]) :: binary
  def create(repo, oids) when is_list(oids) do
    with {:ok, walk} <- Git.revwalk_new(repo),
         :ok <- walk_insert(walk, oid_mask(oids)),
         {:ok, pack} <- Git.revwalk_pack(walk),
         do: pack
  end

  @doc """
  Returns a list of ODB objects and their type for the given *PACK* `data`.
  """
  @spec parse(binary) :: {obj_list, binary}
  def parse("PACK" <> pack), do: parse(pack)
  def parse(<<version::32, count::32, data::binary>> = _pack), do: unpack(version, count, data)

  #
  # Helpers
  #

  defp walk_insert(_walk, []), do: :ok

  defp walk_insert(walk, [{oid, hide} | oids]) do
    case Git.revwalk_push(walk, oid, hide) do
      :ok -> walk_insert(walk, oids)
      {:error, reason} -> {:error, reason}
    end
  end

  defp oid_mask(oids) do
    Enum.map(oids, fn
      {oid, hidden} when is_binary(oid) -> {oid, hidden}
      oid when is_binary(oid) -> {oid, false}
    end)
  end

  defp unpack(2 = _version, count, data) do
    unpack_obj_next(0, count, data, [])
  end

  defp unpack_obj_next(i, max, rest, acc) when i < max do
    {obj_type, obj, rest} = unpack_obj(rest)
    unpack_obj_next(i + 1, max, rest, [{obj_type, obj} | acc])
  end

  defp unpack_obj_next(max, max, rest, acc) do
    <<_checksum::binary-20, rest::binary>> = rest
    {Enum.reverse(acc), rest}
  end

  defp unpack_obj(data) do
    {id_type, inflate_size, rest} = unpack_obj_head(data)
    obj_type = format_obj_type(id_type)
    Logger.debug("unpack #{obj_type} (#{inflate_size} bytes)")

    cond do
      obj_type == :delta_reference ->
        <<base_oid::binary-20, rest::binary>> = rest
        {delta, rest} = unpack_obj_data(rest)

        if byte_size(delta) != inflate_size,
          do:
            raise(
              "inflate delta does not match given size: #{inflate_size} != #{byte_size(delta)}"
            )

        {obj_type, unpack_obj_delta(base_oid, delta), rest}

      true ->
        {obj_data, rest} = unpack_obj_data(rest)

        if byte_size(obj_data) != inflate_size,
          do:
            raise(
              "inflate object does not match given size: #{inflate_size} != #{byte_size(obj_data)}"
            )

        {obj_type, obj_data, rest}
    end
  end

  defp unpack_obj_head(<<0::1, type::3, num::4, rest::binary>>), do: {type, num, rest}

  defp unpack_obj_head(<<1::1, type::3, num::4, rest::binary>>) do
    {size, rest} = unpack_obj_size(rest, num, 0)
    {type, size, rest}
  end

  defp unpack_obj_size(<<0::1, num::7, rest::binary>>, acc, i),
    do: {acc + (num <<< (4 + 7 * i)), rest}

  defp unpack_obj_size(<<1::1, num::7, rest::binary>>, acc, i) do
    unpack_obj_size(rest, acc + (num <<< (4 + 7 * i)), i + 1)
  end

  defp unpack_obj_data(data) do
    {:ok, obj, deflate_size} = Git.object_zlib_inflate(data)
    {IO.iodata_to_binary(obj), binary_part(data, deflate_size, byte_size(data) - deflate_size)}
  end

  defp unpack_obj_delta(base_oid, delta) do
    {base_obj_size, rest} = unpack_obj_delta_size(delta, 0, 0)
    {result_obj_size, rest} = unpack_obj_delta_size(rest, 0, 0)
    {base_oid, base_obj_size, result_obj_size, unpack_obj_delta_hunk(rest, [])}
  end

  defp unpack_obj_delta_size(<<0::1, num::7, rest::binary>>, acc, i),
    do: {acc ||| num <<< (7 * i), rest}

  defp unpack_obj_delta_size(<<1::1, num::7, rest::binary>>, acc, i) do
    unpack_obj_delta_size(rest, acc ||| num <<< (7 * i), i + 1)
  end

  defp unpack_obj_delta_hunk(<<0::1, size::7, data::binary-size(size), rest::binary>>, cmds) do
    unpack_obj_delta_hunk(rest, [{:insert, data} | cmds])
  end

  defp unpack_obj_delta_hunk(<<1::1, l::bitstring-3, o::bitstring-4, rest::binary>>, cmds) do
    # Thanks to @vaibhavsagar on #haskell
    len_bits = delta_copy_length_size(l)
    ofs_bits = delta_copy_offset_size(o)

    try do
      <<offset::little-size(ofs_bits), size::little-size(len_bits), rest::binary>> = rest
      unpack_obj_delta_hunk(rest, [{:copy, {offset, size}} | cmds])
    rescue
      MatchError ->
        Logger.error("skip invalid delta copy command")
        unpack_obj_delta_hunk(rest, cmds)
    end
  end

  defp unpack_obj_delta_hunk("", cmds), do: Enum.reverse(cmds)

  defp unpack_obj_delta_hunk(<<char::8, rest::binary>>, cmds) do
    Logger.warn("skip invalid delta char #{inspect(char)}")
    unpack_obj_delta_hunk(rest, cmds)
  end

  defp delta_copy_length_size(<<_::1, _::1, 0::1>>), do: 0x10000
  defp delta_copy_length_size(<<_::1, 0::1, 1::1>>), do: 8
  defp delta_copy_length_size(<<0::1, 1::1, 1::1>>), do: 16
  defp delta_copy_length_size(<<1::1, 1::1, 1::1>>), do: 24

  defp delta_copy_offset_size(<<_::1, _::1, _::1, 0::1>>), do: 0
  defp delta_copy_offset_size(<<_::1, _::1, 0::1, 1::1>>), do: 8
  defp delta_copy_offset_size(<<_::1, 0::1, 1::1, 1::1>>), do: 16
  defp delta_copy_offset_size(<<0::1, 1::1, 1::1, 1::1>>), do: 24
  defp delta_copy_offset_size(<<1::1, 1::1, 1::1, 1::1>>), do: 32

  defp format_obj_type(1), do: :commit
  defp format_obj_type(2), do: :tree
  defp format_obj_type(3), do: :blob
  defp format_obj_type(4), do: :tag
  defp format_obj_type(6), do: :delta_offset
  defp format_obj_type(7), do: :delta_reference
end
