#pragma once

#include <QImage>
#include <QObject>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>

// Everything that reaches outside the window: launching, the clipboard, dragging to other applications, and the facts about a file the listing does not carry.
class System : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(QString initialPath READ initialPath CONSTANT)
    Q_PROPERTY(bool prefersReducedMotion READ prefersReducedMotion CONSTANT)
    Q_PROPERTY(QStringList clipboardPaths READ clipboardPaths NOTIFY clipboardChanged)
    Q_PROPERTY(bool isClipboardCut READ isClipboardCut NOTIFY clipboardChanged)

public:
    explicit System(QObject *parent = nullptr);

    QString homePath() const;
    QString initialPath() const;
    bool prefersReducedMotion() const { return m_prefersReducedMotion; }
    QStringList clipboardPaths() const { return m_clipboardPaths; }
    bool isClipboardCut() const { return m_isClipboardCut; }

    static void setInitialPath(const QString &path);

    Q_INVOKABLE void open(const QString &path);
    Q_INVOKABLE QVariantList applicationsFor(const QString &path) const;
    Q_INVOKABLE void openWith(const QString &desktopFile, const QStringList &paths);
    Q_INVOKABLE void openTerminal(const QString &directory, const QString &command);
    Q_INVOKABLE void copyPaths(const QStringList &paths, bool isCut);
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void clearClipboard();
    // Blocks in a nested loop until the drop lands, the way every toolkit drag does; returns the Qt.DropAction the target chose.
    Q_INVOKABLE int startDrag(const QStringList &paths, const QVariant &image, int hotX, int hotY);
    Q_INVOKABLE int keyboardModifiers() const;
    Q_INVOKABLE QStringList completePath(const QString &text) const;
    Q_INVOKABLE QVariantMap details(const QString &path) const;
    Q_INVOKABLE QString textPreview(const QString &path, int maximumBytes) const;
    Q_INVOKABLE void measureFolder(const QString &path);
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE bool isDirectory(const QString &path) const;
    Q_INVOKABLE bool isWritable(const QString &path) const;
    Q_INVOKABLE QString parentOf(const QString &path) const;
    Q_INVOKABLE QString nameOf(const QString &path) const;
    Q_INVOKABLE QString formatSize(qint64 bytes) const;
    Q_INVOKABLE QString expandPath(const QString &text) const;
    Q_INVOKABLE QStringList localPaths(const QVariantList &urls) const;

signals:
    void clipboardChanged();
    void folderMeasured(const QString &path, qint64 bytes, int files, int folders);

private:
    void readClipboard();
    void handClipboardOver();

    std::shared_ptr<std::atomic_bool> m_measureCancel;
    QStringList m_clipboardPaths;
    bool m_isClipboardCut = false;
    bool m_prefersReducedMotion = false;
};
