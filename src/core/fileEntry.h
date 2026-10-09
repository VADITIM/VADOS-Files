#pragma once

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QString>

// One row of a folder as the interface reads it. Built off the GUI thread, so it holds values only — never a QFileInfo that would stat again when read.
struct FileEntry {
    QString name;
    QString path;
    QString mimeType;
    QString kind;
    QString suffix;
    QString linkTarget;
    QString originalPath;
    QDateTime modified;
    QDateTime deletedAt;
    qint64 size = 0;
    int childCount = -1;
    bool isDirectory = false;
    bool isHidden = false;
    bool isSymlink = false;
    bool isExecutable = false;
};

// #region ── kind ────────────────────────────────────────────────────────────────────────────

// The kind is what the glyph and the accent tint are chosen by; the mime type is too fine-grained to draw.
inline QString kindForMime(const QMimeType &mimeType, const QString &suffix, bool isDirectory, bool isExecutable)
{
    if (isDirectory)
        return QStringLiteral("folder");
    const QString name = mimeType.name();
    if (name.startsWith(QLatin1String("image/")))
        return QStringLiteral("image");
    if (name.startsWith(QLatin1String("video/")))
        return QStringLiteral("video");
    if (name.startsWith(QLatin1String("audio/")))
        return QStringLiteral("audio");
    static const QStringList archiveSuffixes = {
        QStringLiteral("zip"), QStringLiteral("tar"), QStringLiteral("gz"), QStringLiteral("xz"),
        QStringLiteral("zst"), QStringLiteral("bz2"), QStringLiteral("7z"), QStringLiteral("rar"),
        QStringLiteral("tgz"), QStringLiteral("txz"), QStringLiteral("iso"), QStringLiteral("deb"),
        QStringLiteral("rpm"), QStringLiteral("jar"), QStringLiteral("apk")};
    if (archiveSuffixes.contains(suffix) || name.contains(QLatin1String("archive")) || name.contains(QLatin1String("compressed")))
        return QStringLiteral("archive");
    static const QStringList codeSuffixes = {
        QStringLiteral("c"), QStringLiteral("h"), QStringLiteral("cpp"), QStringLiteral("hpp"),
        QStringLiteral("cc"), QStringLiteral("rs"), QStringLiteral("go"), QStringLiteral("py"),
        QStringLiteral("js"), QStringLiteral("ts"), QStringLiteral("tsx"), QStringLiteral("jsx"),
        QStringLiteral("vue"), QStringLiteral("svelte"), QStringLiteral("qml"), QStringLiteral("java"),
        QStringLiteral("kt"), QStringLiteral("cs"), QStringLiteral("gd"), QStringLiteral("lua"),
        QStringLiteral("sh"), QStringLiteral("fish"), QStringLiteral("zsh"), QStringLiteral("json"),
        QStringLiteral("toml"), QStringLiteral("yaml"), QStringLiteral("yml"), QStringLiteral("xml"),
        QStringLiteral("html"), QStringLiteral("css"), QStringLiteral("scss"), QStringLiteral("glsl"),
        QStringLiteral("frag"), QStringLiteral("vert"), QStringLiteral("conf"), QStringLiteral("ini"),
        QStringLiteral("cmake"), QStringLiteral("tscn"), QStringLiteral("tres")};
    if (codeSuffixes.contains(suffix))
        return QStringLiteral("code");
    static const QStringList documentSuffixes = {
        QStringLiteral("pdf"), QStringLiteral("doc"), QStringLiteral("docx"), QStringLiteral("odt"),
        QStringLiteral("xls"), QStringLiteral("xlsx"), QStringLiteral("ods"), QStringLiteral("ppt"),
        QStringLiteral("pptx"), QStringLiteral("odp"), QStringLiteral("epub"), QStringLiteral("rtf")};
    if (documentSuffixes.contains(suffix))
        return QStringLiteral("document");
    if (name.startsWith(QLatin1String("text/")) || name == QLatin1String("application/x-zerosize"))
        return QStringLiteral("text");
    if (isExecutable || name == QLatin1String("application/x-executable") || name == QLatin1String("application/x-sharedlib"))
        return QStringLiteral("executable");
    return QStringLiteral("file");
}

inline FileEntry entryFromInfo(const QFileInfo &info, const QMimeDatabase &mimeDatabase, bool shouldCountChildren)
{
    FileEntry entry;
    entry.name = info.fileName();
    entry.path = info.absoluteFilePath();
    entry.isSymlink = info.isSymLink();
    entry.linkTarget = entry.isSymlink ? info.symLinkTarget() : QString();
    entry.isDirectory = info.isDir();
    entry.isHidden = entry.name.startsWith(QLatin1Char('.'));
    entry.isExecutable = !entry.isDirectory && info.isExecutable();
    entry.size = entry.isDirectory ? 0 : info.size();
    entry.modified = info.lastModified();
    entry.suffix = info.suffix().toLower();
    // Extension matching only: content sniffing reads every file in the folder and turns a listing into a disk scan.
    const QMimeType mimeType = entry.isDirectory ? mimeDatabase.mimeTypeForName(QStringLiteral("inode/directory"))
                                                 : mimeDatabase.mimeTypeForFile(info, QMimeDatabase::MatchExtension);
    entry.mimeType = mimeType.name();
    entry.kind = kindForMime(mimeType, entry.suffix, entry.isDirectory, entry.isExecutable);
    if (entry.isDirectory && shouldCountChildren) {
        QDir directory(entry.path);
        entry.childCount = directory.isReadable() ? int(directory.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System).size()) : -1;
    }
    return entry;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
