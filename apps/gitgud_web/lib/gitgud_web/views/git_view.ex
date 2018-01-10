defmodule GitGud.Web.GitView do
  @moduledoc false
  use GitGud.Web, :view

  alias GitRekt.Git

  def render("branch_list.json", %{references: refs, repository: repository}) do
    render_many(refs, __MODULE__, "branch.json", as: :reference, repository: repository)
  end

  def render("branch.json", %{reference: {oid, _refname, shorthand, commit}, repository: repository}) do
    %{sha: Git.oid_fmt(oid),
      name: shorthand,
      commit: render_one({oid, commit}, __MODULE__, "commit.json", as: :commit, repository: repository),
      url: repository_url(GitGud.Web.Endpoint, :branch, repository.owner, repository.path, shorthand)}
  end

  def render("tag_list.json", %{references: refs, repository: repository}) do
    render_many(refs, __MODULE__, "tag.json", as: :tag, repository: repository)
  end

  def render("tag.json", %{tag: {oid, tag}, repository: repository}) do
    with {:ok, name} <- Git.tag_name(tag),
         {:ok, message} <- Git.tag_message(tag),
         {:ok, author, email, time, offset} <- Git.tag_author(tag),
         {:ok, :commit, ^oid, commit} = Git.tag_peel(tag), do:
      %{type: :annotated,
        sha: Git.oid_fmt(oid),
		name: name,
		message: message,
		author: render_one({author, email, time, offset}, __MODULE__, "signature.json", as: :signature, repository: repository),
        commit: render_one({oid, commit}, __MODULE__, "commit.json", as: :commit, repository: repository),
        url: repository_url(GitGud.Web.Endpoint, :tag, repository.owner, repository.path, name)}
  end

  def render("tag.json", %{tag: {oid, commit, shorthand}, repository: repository}) do
    %{type: :lightweight,
      sha: Git.oid_fmt(oid),
      name: shorthand,
      commit: render_one({oid, commit}, __MODULE__, "commit.json", as: :commit, repository: repository),
      url: repository_url(GitGud.Web.Endpoint, :tag, repository.owner, repository.path, shorthand)}
  end

  def render("revwalk.json", %{commits: commits, repository: repository}) do
    render_many(commits, __MODULE__, "commit.json", as: :commit, repository: repository)
  end

  def render("signature.json", %{signature: {name, email, time, _offset}}) do
    with {:ok, date_time} <- DateTime.from_unix(time), do:
      %{name: name,
        email: email,
        date: DateTime.to_iso8601(date_time)}
  end

  def render("commit.json", %{commit: {oid, commit}, repository: repository}) do
    with {:ok, message} <- Git.commit_message(commit),
         {:ok, author, email, time, offset} <- Git.commit_author(commit), do:
      %{sha: Git.oid_fmt(oid),
        message: message,
        author: render_one({author, email, time, offset}, __MODULE__, "signature.json", as: :signature, repository: repository),
        url: repository_url(GitGud.Web.Endpoint, :commit, repository.owner, repository.path, Git.oid_fmt(oid))}
  end

  def render("tree.json", %{spec: spec, path: path, tree: tree, repository: repository}) do
    render_many(tree, __MODULE__, "tree_entry.json", as: :entry, repository: repository, spec: spec, path: path)
  end

  def render("tree_entry.json", %{entry: {mode, type, oid, name}, repository: repository, spec: spec, path: _path}) do
    path = name
    %{sha: Git.oid_fmt(oid),
      type: type,
      mode: mode,
      path: path,
      url: repository_url(GitGud.Web.Endpoint, controller_action_for_tree(type), repository.owner, repository.path, spec, Path.split(path))}
  end

  #
  # Helpers
  #

  defp controller_action_for_tree(:tree), do: :browse_tree
  defp controller_action_for_tree(:blob), do: :download_blob
end

