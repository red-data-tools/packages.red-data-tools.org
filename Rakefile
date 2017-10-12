# -*- ruby -*-

require_relative "repository-task"

repository_task = RepositoryTask.new
repository_task.define

desc "Apply the Ansible configurations"
task :deploy do
  sh("ansible-playbook",
     "--inventory-file", "ansible/hosts",
     "ansible/playbook.yml")
end
