require File.expand_path("#{File.dirname(__FILE__)}/../test_helper")

class TestGitSvn < Piston::TestCase
  attr_reader :root_path, :parent_path, :repos_path, :wc_path

  def setup
    super
    @root_path = mkpath("/tmp/import_git_svn")

    @repos_path = @root_path + "repos"

    @parent_path = root_path + "parent"
    mkpath(parent_path)

    @wc_path = root_path + "wc"
    mkpath(wc_path)

    Dir.chdir(parent_path) do
      git(:init)
      File.open("README", "wb") {|f| f.write "Readme - first commit\n"}
      File.open("file_in_first_commit", "wb") {|f| f.write "file_in_first_commit"}
      File.open("file_to_rename", "wb") {|f| f.write "file_to_rename"}
      File.open("file_to_copy", "wb") {|f| f.write "file_to_copy"}
      File.open("conflicting_file", "wb") {|f| f.write "conflicting_file\n"}
      git(:add, ".")
      git(:commit, "-m", "'first commit'")
    end

    svnadmin :create, repos_path
    svn :checkout, "file://#{repos_path}", wc_path
    svn :mkdir, wc_path + "trunk", wc_path + "tags", wc_path + "branches", wc_path + "trunk/vendor"
    svn :commit, wc_path, "--message", "'first commit'"
  end

  def test_import
    piston(:import, parent_path, wc_path + "trunk/vendor/parent")

    assert_equal ADD_STATUS.split("\n").sort, svn(:status, wc_path + "trunk/vendor").gsub((wc_path + "trunk/").to_s, "").split("\n").sort

    info = YAML.load_file(wc_path + "trunk/vendor/parent/.piston.yml")
    assert_equal 1, info["format"]
    assert_equal parent_path.to_s, info["repository_url"]
    assert_equal "Piston::Git::Repository", info["repository_class"]

    response = `git-ls-remote #{parent_path}`
    head_commit = response.grep(/HEAD/).first.chomp.split(/\s+/).first
    assert_equal head_commit, info["handler"][Piston::Git::COMMIT]
  end

  def test_import_from_branch
    Dir.chdir(parent_path) do
      git(:branch, "rewrite")
      git(:checkout, "rewrite")
      touch("file_in_branch")
      git(:add, ".")
      git(:commit, "-m", "'commit after branch'")
    end
    piston(:import, "--revision", "origin/rewrite", parent_path, wc_path + "trunk/vendor/parent")

    assert File.exists?(wc_path + "trunk/vendor/parent/file_in_branch"),
        "Could not find file_in_branch in parent imported directory."

    info = YAML.load(File.read(wc_path + "trunk/vendor/parent/.piston.yml"))
    assert_equal 1, info["format"]
    assert_equal parent_path.to_s, info["repository_url"]
    assert_equal "Piston::Git::Repository", info["repository_class"]

    response = `git-ls-remote #{parent_path}`
    head_commit = response.grep(/refs\/heads\/rewrite/).first.chomp.split(/\s+/).first
    assert_equal head_commit, info["handler"][Piston::Git::COMMIT]
    assert_equal "origin/rewrite", info["handler"][Piston::Git::BRANCH]
  end

  def test_import_from_tag
    Dir.chdir(parent_path) do
      git(:tag, "the_tag_name")
      touch("file_past_tag")
      git(:add, ".")
      git(:commit, "-m", "'commit after tag'")
    end
    piston(:import, "--revision", "the_tag_name", parent_path, wc_path + "trunk/vendor/parent")

    info = YAML.load(File.read(wc_path + "trunk/vendor/parent/.piston.yml"))
    assert_equal 1, info["format"]
    assert_equal parent_path.to_s, info["repository_url"]
    assert_equal "Piston::Git::Repository", info["repository_class"]

    response = `git-ls-remote #{parent_path} the_tag_name`
    tagged_commit = response.chomp.split(/\s+/).first
    assert_equal tagged_commit, info["handler"][Piston::Git::COMMIT]
    assert_equal "the_tag_name", info["handler"][Piston::Git::BRANCH]
  end

  ADD_STATUS = %Q(A      vendor/parent
A      vendor/parent/.piston.yml
A      vendor/parent/README
A      vendor/parent/file_in_first_commit
A      vendor/parent/file_to_rename
A      vendor/parent/file_to_copy
A      vendor/parent/conflicting_file
)

  def test_update
    piston(:import, parent_path, wc_path + "trunk/vendor/parent")
    svn(:commit, "-m", "'import'", wc_path)

    # change mode to "ab" to get a conflict when it's implemented
    File.open(wc_path + "trunk/vendor/parent/README", "wb") do |f|
      f.write "Readme - modified after imported\nReadme - first commit\n"
    end
    File.open(wc_path + "trunk/vendor/parent/conflicting_file", "ab") do |f|
      f.write "working copy\n"
    end
    svn(:commit, "-m", "'next commit'", wc_path)

    Dir.chdir(parent_path) do
      File.open("README", "ab") {|f| f.write "Readme - second commit\n"}
      File.open("conflicting_file", "ab") {|f| f.write "parent repository\n"}
      git(:rm, "file_in_first_commit")
      File.open("file_in_second_commit", "wb") {|f| f.write "file_in_second_commit"}
      FileUtils.cp("file_to_copy", "copied_file")
      git(:mv, "file_to_rename", "renamed_file")
      git(:add, ".")
      git(:commit, "-m", "'second commit'")
    end

    piston(:update, wc_path + "trunk/vendor/parent")
    
    assert_equal CHANGE_STATUS.split("\n").sort, svn(:status, wc_path + "trunk/vendor").gsub((wc_path + "trunk/").to_s, "").split("\n").sort
    assert_equal README, File.read(wc_path + "trunk/vendor/parent/README")
    assert_equal CONFLICT, File.read(wc_path + "trunk/vendor/parent/conflicting_file")
  end

  CHANGE_STATUS = %Q(M      vendor/parent/.piston.yml
M      vendor/parent/README
A      vendor/parent/file_in_second_commit
D      vendor/parent/file_in_first_commit
A      vendor/parent/copied_file
D      vendor/parent/file_to_rename
A  +   vendor/parent/renamed_file
C      vendor/parent/conflicting_file
?      vendor/parent/conflicting_file.mine
?      vendor/parent/conflicting_file.r2
?      vendor/parent/conflicting_file.r3
)
  README = %Q(Readme - modified after imported
Readme - first commit
Readme - second commit
)
  CONFLICT = %Q(conflicting_file
<<<<<<< .mine
parent repository
=======
working copy
>>>>>>> .r3
)
end
