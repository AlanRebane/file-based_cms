ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document("history.txt", "Ruby 0.95 released")

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]

    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_document_not_found
    get "/notafile.ext" # Attempt to access a nonexistent file
  
    assert_equal 302, last_response.status # Assert that the user was redirected
    assert_equal "notafile.ext does not exist.", session[:message]
  
    get last_response["Location"] # Request the page that the user was redirected to
  
    assert_equal 200, last_response.status
  
    get "/" # Reload the page
    refute_includes last_response.body, "notafile.ext does not exist" # Assert that our message has been removed
  end

  def test_viewing_markdown_document
    create_document("about.md", "# Ruby is...")

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]

    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_document_editing
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_updating_document
    post "/changes.txt", {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_create_new_file
    post "/create", {filename: "myfile.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "myfile.txt has been created.", session[:message]
    
    get "/"
    assert_includes last_response.body, "myfile.txt"
  end

  def test_create_new_document_without_filename
    post "/create", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_delete_a_document
    create_document("myfile.txt")

    post "/myfile.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "myfile.txt has been deleted.", session[:message]
    
    get "/"
    refute_includes last_response.body, %q(href="/myfiles.txt")
  end

  def test_signin_form
    get "/users/signin"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input type="password")
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_sign_out
    post "/users/signin", username: "admin", password: "secret"
    get last_response["Location"]
    
    post "/users/signout"
    assert_equal 302, last_response.status
    assert_equal "You have been signed out!", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Sign In"
    assert_nil session[:username]
  end

  def test_sign_in_with_admin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_sign_in_with_invalid_credentials
    post "/users/signin", username: "admin", password: "not_secret"
    assert_equal 422, last_response.status
    assert_nil session[:username]

    assert_includes last_response.body, "Invalid Credentials!"
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def test_try_with_signed_out_user
    create_document("myfile.txt")

    get "/myfile.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    post "/myfile.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    post "/create"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]

    post "/myfile.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
end