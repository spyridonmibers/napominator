# Добавляет в ios/Runner.xcodeproj расширение GoalsLive (Live Activity / Dynamic Island).
# Запускается на macOS из tool/setup_platforms.sh. Гем xcodeproj идёт вместе с CocoaPods.
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('../..', __dir__)
ios = File.join(root, 'ios')
extra = File.join(root, 'tool/ios_extra')

# Файлы кладём всегда (идемпотентно)
FileUtils.mkdir_p(File.join(ios, 'GoalsLive'))
FileUtils.mkdir_p(File.join(ios, 'Shared'))
FileUtils.cp(Dir[File.join(extra, 'GoalsLive/*')], File.join(ios, 'GoalsLive'))
FileUtils.cp(File.join(extra, 'Shared/GoalsActivity.swift'), File.join(ios, 'Shared'))
FileUtils.cp(Dir[File.join(extra, 'Runner/*.swift')], File.join(ios, 'Runner'))
FileUtils.mkdir_p(File.join(ios, 'Runner/Sounds'))
FileUtils.cp(Dir[File.join(root, 'tool/sounds/ios/*.caf')], File.join(ios, 'Runner/Sounds'))

project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))

# Альтернативные иконки (AppIcon-*.appiconset кладёт tool/patch_platforms.py)
alt_icons = Dir[File.join(ios, 'Runner/Assets.xcassets/AppIcon-*.appiconset')].map { |d| File.basename(d, '.appiconset') }.sort
runner_target = project.targets.find { |t| t.name == 'Runner' }
if runner_target && !alt_icons.empty?
  runner_target.build_configurations.each do |c|
    c.build_settings['ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES'] = alt_icons.join(' ')
    c.build_settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] = 'NO'
  end
  project.save
end

# Будильник: мост к AlarmKit и мелодии в бандле приложения
if runner_target
  runner_group0 = project.main_group.find_subpath('Runner', false)
  if runner_group0 && runner_group0.files.none? { |f| f.path == 'AlarmBridge.swift' }
    ref = runner_group0.new_reference('AlarmBridge.swift')
    runner_target.add_file_references([ref])
  end
  sounds_group = runner_group0.children.find { |g| g.respond_to?(:path) && g.path == 'Sounds' } ||
                 runner_group0.new_group('Sounds', 'Sounds')
  Dir[File.join(ios, 'Runner/Sounds/*.caf')].sort.each do |f|
    name = File.basename(f)
    next if sounds_group.files.any? { |x| x.path == name }
    ref = sounds_group.new_reference(name)
    runner_target.resources_build_phase.add_file_reference(ref, true)
  end
  project.save
end

if project.targets.any? { |t| t.name == 'GoalsLive' }
  puts 'GoalsLive уже добавлен'
  exit 0
end

app = project.targets.find { |t| t.name == 'Runner' } or abort('Не найден таргет Runner')
runner_group = project.main_group.find_subpath('Runner', false) or abort('Не найдена группа Runner')

plugin_ref = runner_group.new_reference('LiveGoalsPlugin.swift')
shared_group = project.main_group.new_group('Shared', 'Shared')
shared_ref = shared_group.new_reference('GoalsActivity.swift')
app.add_file_references([plugin_ref, shared_ref])

ext = project.new_target(:app_extension, 'GoalsLive', :ios, '16.2')
ext.add_build_configuration('Profile', :release) unless ext.build_configurations.any? { |c| c.name == 'Profile' }

ext_group = project.main_group.new_group('GoalsLive', 'GoalsLive')
bundle_ref = ext_group.new_reference('GoalsLiveBundle.swift')
widget_ref = ext_group.new_reference('GoalsLiveWidget.swift')
ext_group.new_reference('Info.plist')
ext.add_file_references([bundle_ref, widget_ref, shared_ref])

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'ru.napominator.napominator.GoalsLive'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'GoalsLive/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
  s['MARKETING_VERSION'] = '1.0.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['CODE_SIGN_STYLE'] = 'Automatic'
end

# Встраиваем .appex в приложение
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(ext)

# Фаза встраивания должна идти до «Thin Binary», иначе Xcode ругается на цикл сборки.
app.build_phases.delete(embed)
idx = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' } || app.build_phases.length
app.build_phases.insert(idx, embed)

project.save
puts 'Расширение GoalsLive добавлено'
