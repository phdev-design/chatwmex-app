require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  if target.name == 'NotificationExtension'
    target.build_configurations.each do |config|
      config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    end
    
    # Remove Info.plist from Copy Bundle Resources phase to avoid duplicate
    target.resources_build_phase.files.each do |file|
      if file.file_ref && file.file_ref.path && file.file_ref.path.include?('Info.plist')
        puts "Removing #{file.file_ref.path} from #{target.name} Resources Build Phase"
        file.remove_from_project
      end
    end
  end
end
project.save
puts "Successfully patched project.pbxproj"
