# -*- ruby -*-

require_relative "helper"
require_relative "repository-task"

class RedDataToolsRepositoryTask < RepositoryTask
  include Helper::Repository

  private
  def repository_gpg_key_id
    repository_gpg_key_ids.first
  end
end

repository_task = RedDataToolsRepositoryTask.new
repository_task.define

user = ENV["ANSIBLE_GPG_USER"] || ENV["USER"]
file "ansible/password" => "ansible/password.#{user}.asc" do |task|
  sh("gpg",
     "--output", task.name,
     "--decrypt", task.prerequisites.first)
  chmod(0600, task.name)
end

desc "Apply the Ansible configurations"
task :deploy do
  sh("ansible-playbook",
     "--inventory", "ansible/hosts",
     "--vault-password-file", "ansible/password",
     "ansible/playbook.yml")
end

desc "Tag"
task :tag do
  version = repository_task.repository_version
  sh("git", "tag", "-a", version, "-m", "Publish #{version}")
  sh("git", "push", "--tags")
end
