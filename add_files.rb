require 'xcodeproj'
project_path = 'macos/Ponten.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Add missing files in Views
views_group = project.main_group.find_subpath(File.join('Ponten', 'Views'), true)
Dir.glob("macos/Ponten/Views/*.swift").each do |file|
  basename = File.basename(file)
  next if views_group.files.any? { |f| f.path == basename }
  
  puts "Adding #{basename}"
  file_ref = views_group.new_file(basename)
  target.add_file_references([file_ref])
end

# Add missing files in Models
models_group = project.main_group.find_subpath(File.join('Ponten', 'Models'), true)
Dir.glob("macos/Ponten/Models/*.swift").each do |file|
  basename = File.basename(file)
  next if models_group.files.any? { |f| f.path == basename }

  puts "Adding model #{basename}"
  file_ref = models_group.new_file(basename)
  target.add_file_references([file_ref])
end

# Add missing files in Utilities
utilities_group = project.main_group.find_subpath(File.join('Ponten', 'Utilities'), true)
Dir.glob("macos/Ponten/Utilities/*.swift").each do |file|
  basename = File.basename(file)
  next if utilities_group.files.any? { |f| f.path == basename }

  puts "Adding utility #{basename}"
  file_ref = utilities_group.new_file(basename)
  target.add_file_references([file_ref])
end

# Also add Tests if missing
test_target = project.targets.find { |t| t.name == 'PontenTests' }
if test_target
  tests_group = project.main_group.find_subpath('PontenTests', true)
  Dir.glob("macos/PontenTests/*.swift").each do |file|
    basename = File.basename(file)
    next if tests_group.files.any? { |f| f.path == basename }
    
    puts "Adding test file #{basename}"
    file_ref = tests_group.new_file(basename)
    test_target.add_file_references([file_ref])
  end
end

project.save
