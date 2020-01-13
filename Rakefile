# -*- ruby -*-

require_relative "helper"
require_relative "repository-task"

class RedDataToolsRepositoryTask < RepositoryTask
  include Helper::Repository

  private
  def rsync_base_path
    repository_rsync_base_path
  end

  def gpg_uids
    repository_gpg_uids
  end
end

repository_task = RedDataToolsRepositoryTask.new
repository_task.define

desc "Apply the Ansible configurations"
task :deploy do
  sh("ansible-playbook",
     "--inventory-file", "ansible/hosts",
     "ansible/playbook.yml")
end

desc "Tag"
task :tag do
  version = repository_task.repository_version
  sh("git", "tag", "-a", version, "-m", "Publish #{version}")
  sh("git", "push", "--tags")
end
