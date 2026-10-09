cmake_minimum_required(VERSION 3.21)
project(vados-files VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Svg Concurrent DBus ShaderTools)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(vados-files
    src/main.cpp
    src/fileManagerService.h src/fileManagerService.cpp
    src/portalService.h src/portalService.cpp
)

set_source_files_properties(qml/design/Theme.qml qml/design/Motion.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(vados-files
    URI Vados
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    SOURCES
        src/core/fileEntry.h
        src/core/folderModel.h src/core/folderModel.cpp
        src/core/fileOperations.h src/core/fileOperations.cpp
        src/core/placesModel.h src/core/placesModel.cpp
        src/core/imageProviders.h src/core/imageProviders.cpp
        src/core/system.h src/core/system.cpp
        src/core/settings.h
        src/core/picker.h src/core/picker.cpp
    QML_FILES
        qml/Main.qml
        qml/design/Theme.qml
        qml/design/Motion.qml
        qml/ui/Squircle.qml
        qml/ui/SquircleImage.qml
        qml/ui/Module.qml
        qml/ui/Reveal.qml
        qml/ui/Glyph.qml
        qml/ui/IconButton.qml
        qml/ui/FadeText.qml
        qml/ui/Slices.qml
        qml/ui/GooStepSlider.qml
        qml/ui/Pill.qml
        qml/ui/MenuSheet.qml
        qml/ui/MenuRow.qml
        qml/ui/Toggle.qml
        qml/ui/ThinScrollBar.qml
        qml/feature/FolderPane.qml
        qml/feature/FileTile.qml
        qml/feature/FileRow.qml
        qml/feature/RenameField.qml
        qml/feature/DropHint.qml
        qml/feature/PlaceRow.qml
        qml/feature/SearchField.qml
        qml/feature/PathBar.qml
        qml/feature/PlacesModule.qml
        qml/feature/DetailsModule.qml
        qml/feature/TransfersModule.qml
        qml/feature/TabStrip.qml
        qml/feature/DragStack.qml
        qml/feature/QuickLook.qml
        qml/feature/PickerBar.qml
        qml/feature/ConfirmHost.qml
        qml/feature/ContextMenu.qml
        qml/feature/SettingsSheet.qml
        qml/feature/Toolbar.qml
        qml/feature/ControlRow.qml
        qml/feature/IconPicker.qml
        qml/feature/Workspace.qml
    RESOURCES
        assets/glyphs/folder.svg
        assets/glyphs/star.svg
        assets/glyphs/heart.svg
        assets/glyphs/flag.svg
        assets/glyphs/cpu.svg
        assets/glyphs/flask.svg
        assets/glyphs/briefcase.svg
        assets/glyphs/book.svg
        assets/glyphs/camera.svg
        assets/glyphs/palette.svg
        assets/glyphs/gamepad.svg
        assets/glyphs/cloud.svg
        assets/glyphs/globe.svg
        assets/glyphs/package.svg
        assets/glyphs/bolt.svg
        assets/glyphs/leaf.svg
        assets/glyphs/lock.svg
        assets/glyphs/user.svg
        assets/glyphs/mail.svg
        assets/glyphs/calendar.svg
        assets/glyphs/folder-open.svg
        assets/glyphs/file.svg
        assets/glyphs/image.svg
        assets/glyphs/video.svg
        assets/glyphs/audio.svg
        assets/glyphs/code.svg
        assets/glyphs/text.svg
        assets/glyphs/archive.svg
        assets/glyphs/document.svg
        assets/glyphs/executable.svg
        assets/glyphs/link.svg
        assets/glyphs/home.svg
        assets/glyphs/download.svg
        assets/glyphs/drive.svg
        assets/glyphs/trash.svg
        assets/glyphs/bookmark.svg
        assets/glyphs/back.svg
        assets/glyphs/forward.svg
        assets/glyphs/up.svg
        assets/glyphs/search.svg
        assets/glyphs/grid.svg
        assets/glyphs/list.svg
        assets/glyphs/split.svg
        assets/glyphs/details.svg
        assets/glyphs/settings.svg
        assets/glyphs/plus.svg
        assets/glyphs/close.svg
        assets/glyphs/restore.svg
        assets/glyphs/check.svg
        assets/glyphs/terminal.svg
        assets/glyphs/root.svg
        assets/glyphs/eject.svg
        assets/glyphs/chevron.svg
        assets/glyphs/cut.svg
        assets/glyphs/copy.svg
        assets/glyphs/paste.svg
        assets/glyphs/pencil.svg
)

qt_add_shaders(vados-files "shaders"
    PREFIX /shaders
    BASE shaders
    FILES
        shaders/squircle.frag
        shaders/squircleImage.frag
        shaders/gooRail.frag
        shaders/fadeEdge.frag
        shaders/glyphInk.frag
)

# The fonts are the identity, not a dependency: they are bundled when present and the app falls back to the system faces when they are not (scripts/fetch-fonts.sh).
file(GLOB VADOS_FONTS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} assets/fonts/*.ttf assets/fonts/*.otf)
if(VADOS_FONTS)
    qt_add_resources(vados-files "fonts" PREFIX / FILES ${VADOS_FONTS})
endif()

target_include_directories(vados-files PRIVATE src/core)
target_link_libraries(vados-files PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Svg Qt6::Concurrent Qt6::DBus)

install(TARGETS vados-files RUNTIME DESTINATION bin)
install(FILES packaging/vados-files.desktop DESTINATION share/applications)
install(FILES packaging/org.freedesktop.FileManager1.service packaging/org.freedesktop.impl.portal.desktop.vados.service DESTINATION share/dbus-1/services)
install(FILES packaging/vados.portal DESTINATION share/xdg-desktop-portal/portals)
