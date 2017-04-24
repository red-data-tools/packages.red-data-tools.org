# -*- ruby -*-

desc "Update Apache Arrow packages"
task "apache-arrow" do
  cd("apache-arrow") do
    ruby("-S", "rake", "source", "yum", "apt", "ubuntu")
  end
end

desc "Update Apache Parquet C++ packages"
task "apache-parquet-cpp" do
  cd("apache-parquet-cpp") do
    ruby("-S", "rake", "source", "yum", "apt", "ubuntu")
  end
end

task :default => [
  "apache-arrow",
  "apache-parquet-cpp",
]
