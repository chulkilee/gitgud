import React from "react"
import {QueryRenderer, graphql} from "react-relay"

import environment from "../relay-environment"

class UsersInput extends React.Component {
  constructor(props) {
    super(props)
    this.state = {
      usernames: props.initialUsers,
      input: ""
    }
    this.dropdown = React.createRef()
    this.inputContainer = React.createRef()
    this.inputRestrictedKeys = [13, 32, 188]
    this.renderDropdown = this.renderDropdown.bind(this)
    this.handleFocus = this.handleFocus.bind(this)
    this.handleBlur = this.handleBlur.bind(this)
    this.handleInputChange = this.handleInputChange.bind(this)
    this.handleInputKeyDown = this.handleInputKeyDown.bind(this)
    this.handleAddUser = this.handleAddUser.bind(this)
    this.handleRemoveUser = this.handleRemoveUser.bind(this)
  }

  render() {
    return (
      <div className="users-input dropdown" ref={this.dropdown}>
        <div className="dropdown-trigger">
          <div className="input field is-grouped" ref={this.inputContainer} onFocus={this.handleFocus} onBlur={this.handleBlur}>
            {this.state.usernames.map((user, i) =>
              <div className="control" key={i}>
                <div className="tags has-addons">
                  <a className="tag">{user}</a>
                  <a className="tag is-delete" onClick={this.handleRemoveUser(i)}></a>
                </div>
              </div>
            )}
            <div className="control is-expanded">
              <input type="text" className="input is-static" value={this.state.input} onChange={this.handleInputChange} onKeyDown={this.handleInputKeyDown} />
            </div>
            <input type="hidden" id={this.props.id} name={this.props.name} value={this.state.usernames.join(",")} />
          </div>
        </div>
        <div className="dropdown-menu">
          {this.state.input.length && this.renderDropdown()}
        </div>
      </div>
    )
  }

  renderDropdown() {
    return (
      <div className="dropdown-content">
        <QueryRenderer
          environment={environment}
          query={graphql`
            query UsersInputQuery($input: String!) {
              userSearch(input: $input, first:10) {
                edges {
                  node {
                    username
                    name
                  }
                }
              }
            }
          `}
          variables={{
            input: this.state.input
          }}
          render={({error, props}) => {
            if(error) {
              return <div>{error.message}</div>
            } else if(props) {
              return (
                props.userSearch.edges.filter(edge =>
                  !this.state.usernames.includes(edge.node.username)
                ).map((edge, i) =>
                  <a key={i} className="dropdown-item" onClick={this.handleAddUser(edge.node.username)}>{edge.node.username} <span className="has-text-grey">{edge.node.name}</span></a>
                )
              )
            }
            return <div></div>
          }}
        />
      </div>
    )
  }

  handleFocus() {
    this.inputContainer.current.classList.add("is-focused")
  }

  handleBlur() {
    this.inputContainer.current.classList.remove("is-focused")
  }

  handleInputChange(event) {
    const input = event.target.value
    if(input.length)
      this.dropdown.current.classList.add("is-active")
    else
      this.dropdown.current.classList.remove("is-active")
    this.setState({input: input})
  }

  handleInputKeyDown(event) {
    if(this.inputRestrictedKeys.includes(event.keyCode)) {
      event.preventDefault()
    } else if(event.keyCode == 8 && this.state.usernames.length && !this.state.input.length) {
      this.setState(state => ({
        usernames: state.usernames.slice(0, state.usernames.length - 1)
      }))
    }
  }

  handleAddUser(username) {
    return () => {
      this.dropdown.current.classList.remove("is-active")
      this.setState(state => ({
        usernames: [...state.usernames, username],
        input: ""
      }))
    }
  }

  handleRemoveUser(index) {
    return () => {
      this.setState(state => ({
        usernames: state.usernames.filter((username, i) => i !== index)
      }))
    }
  }
}

export default UsersInput

