#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.expand_path('../macos/Ponten.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

e2e_target = project.targets.find { |t| t.name == 'PontenE2ETests' }
abort('PontenE2ETests target not found') unless e2e_target

ponten_group = project.main_group.find_subpath('Ponten', true)
abort('Ponten group not found') unless ponten_group

EXCLUDED = %w[PontenApp.swift AppDelegate.swift].freeze

def swift_files(group)
  files = []
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      files.concat(swift_files(child))
    elsif child.path&.end_with?('.swift') && !EXCLUDED.include?(File.basename(child.path))
      files << child
    end
  end
  files
end

existing = e2e_target.source_build_phase.files.map { |bf| bf.file_ref&.path }.compact

swift_files(ponten_group).each do |file_ref|
  basename = File.basename(file_ref.path)
  next if existing.include?(basename) || existing.include?(file_ref.path)

  puts "Linking #{basename} into PontenE2ETests"
  e2e_target.add_file_references([file_ref])
end

# Remove AppDelegate if it was linked earlier.
e2e_target.source_build_phase.files.each do |build_file|
  path = build_file.file_ref&.path
  next unless path&.end_with?('AppDelegate.swift')

  puts "Removing #{path} from PontenE2ETests"
  e2e_target.source_build_phase.files.delete(build_file)
end

assets_ref = ponten_group.find_subpath('Resources', true)&.files&.find { |f| f.path == 'Assets.xcassets' }
if assets_ref && e2e_target.resources_build_phase.files.none? { |bf| bf.file_ref == assets_ref }
  puts 'Adding Assets.xcassets to PontenE2ETests resources'
  e2e_target.add_resources([assets_ref])
end

%w[Debug Release].each do |config_name|
  e2e_target.build_configurations.each do |config|
    next unless config.name == config_name

    config.build_settings.delete('TEST_HOST')
    config.build_settings.delete('BUNDLE_LOADER')
  end
end

project.save
puts 'Done.'