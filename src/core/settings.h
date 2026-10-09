#pragma once

#include <QObject>
#include <QSettings>
#include <QtQml/qqmlregistration.h>

// The one storage wrapper every persisted choice goes through (VAS architecture: never raw platform storage).
class Settings : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

#define VADOS_SETTING(Type, name, Name, fallback)                                                   \
    Q_PROPERTY(Type name READ name WRITE set##Name NOTIFY name##Changed)                             \
public:                                                                                            \
    Type name() const { return m_store.value(QStringLiteral(#name), fallback).value<Type>(); }       \
    void set##Name(const Type &value)                                                              \
    {                                                                                              \
        if (name() == value)                                                                       \
            return;                                                                                \
        m_store.setValue(QStringLiteral(#name), value);                                            \
        emit name##Changed();                                                                      \
    }                                                                                              \
    Q_SIGNAL void name##Changed();                                                                 \
                                                                                                   \
private:

    VADOS_SETTING(bool, showHidden, ShowHidden, false)
    VADOS_SETTING(bool, foldersFirst, FoldersFirst, true)
    VADOS_SETTING(QString, viewMode, ViewMode, QStringLiteral("grid"))
    VADOS_SETTING(int, zoomLevel, ZoomLevel, 1)
    VADOS_SETTING(QString, sortKey, SortKey, QStringLiteral("name"))
    VADOS_SETTING(bool, sortDescending, SortDescending, false)
    VADOS_SETTING(bool, isLiteMode, IsLiteMode, false)
    VADOS_SETTING(bool, showDetails, ShowDetails, true)
    VADOS_SETTING(bool, isSplit, IsSplit, false)
    VADOS_SETTING(QString, terminalCommand, TerminalCommand, QString())
    VADOS_SETTING(QString, lastPath, LastPath, QString())
    // The sidebar's width in rem, so it scales with the type; dragged on the divider between the sidebar and the folder.
    VADOS_SETTING(double, sideWidthRem, SideWidthRem, 10.0)
    VADOS_SETTING(int, windowWidth, WindowWidth, 1280)
    VADOS_SETTING(int, windowHeight, WindowHeight, 800)

#undef VADOS_SETTING

public:
    explicit Settings(QObject *parent = nullptr)
        : QObject(parent)
        , m_store(QStringLiteral("vados"), QStringLiteral("files"))
    {
    }

private:
    QSettings m_store;
};
