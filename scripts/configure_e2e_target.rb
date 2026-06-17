#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.expand_path('../macos/Ponten.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

e2e_target = project.targets.find { |t| t.name == 'PontenE2ETests' }
abort('PontenE2ETests target not found') unless e2e_target

ponten_group = project.main_group.find_subpath('Ponten', true)
abort('Ponten group not found') unless ponten_group

# Only compile models/utilities required by E2EMenuPanelView — no SwiftUI views.
ALLOWED_PREFIXES = %w[Models/ Utilities/].freeze
ALLOWED_ROOT = %w[].freeze

def collect_allowed_files(group, prefix = '')
  files = []
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      child_prefix = prefix.empty? ? "#{child.path}/" : "#{prefix}#{child.path}/"
      files.concat(collect_allowed_files(child, child_prefix))
    elsif child.path&.end_with?('.swift')
      rel = "#{prefix}#{child.path}"
      basename = File.basename(child.path)
      allowed = ALLOWED_PREFIXES.any? { |p| rel.start_with?(p) } || ALLOWED_ROOT.include?(basename)
      files << child if allowed
    end
  end
  files
end

allowed_refs = collect_allowed_files(ponten_group).uniq
allowed_basenames = allowed_refs.map { |f| File.basename(f.path) }

# Remove disallowed Ponten sources from the E2E target.
e2e_target.source_build_phase.files.dup.each do |build_file|
  path = build_file.file_ref&.path
  next unless path&.end_with?('.swift')
  next if %w[E2ETestFixture.swift MenuBarE2ETests.swift E2EInProcessHost.swift E2EMenuPanelView.swift].include?(path)

  unless allowed_basenames.include?(path)
    puts "Removing #{path} from PontenE2ETests"
    e2e_target.source_build_phase.files.delete(build_file)
  end
end

existing = e2e_target.source_build_phase.files.map { |bf| bf.file_ref&.path }.compact

allowed_refs.each do |file_ref|
  basename = File.basename(file_ref.path)
  next if existing.include?(basename) || existing.include?(file_ref.path)

  puts "Linking #{basename} into PontenE2ETests"
  e2e_target.add_file_references([file_ref])
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