#include "system.h"

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QDrag>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QMimeData>
#include <QMimeDatabase>
#include <QPixmap>
#include <QPointer>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

namespace {

QString g_initialPath;

const QString GNOME_COPIED_FILES = QStringLiteral("x-special/gnome-copied-files");
const QString KDE_CUT_SELECTION = QStringLiteral("application/x-kde-cutselection");

struct DesktopEntry {
    QString file;
    QString name;
    QStringList mimeTypes;
};

QList<DesktopEntry> readDesktopEntries()
{
    QList<DesktopEntry> entries;
    QStringList seenIds;
    // Earlier directories shadow later ones by desktop id, the same precedence the launcher uses, so a local override of an application wins.
    for (const QString &directory : QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation)) {
        QDirIterator iterator(directory, {QStringLiteral("*.desktop")}, QDir::Files, QDirIterator::Subdirectories);
        while (iterator.hasNext()) {
            const QString file = iterator.next();
            const QString id = QDir(directory).relativeFilePath(file).replace(QLatin1Char('/'), QLatin1Char('-'));
            if (seenIds.contains(id))
                continue;
            seenIds.append(id);
            QSettings desktop(file, QSettings::IniFormat);
            desktop.beginGroup(QStringLiteral("Desktop Entry"));
            if (desktop.value(QStringLiteral("Type")).toString() != QLatin1String("Application") || desktop.value(QStringLiteral("Hidden")).toBool())
                continue;
            const QStringList mimeTypes = desktop.value(QStringLiteral("MimeType")).toString().split(QLatin1Char(';'), Qt::SkipEmptyParts);
            if (mimeTypes.isEmpty())
                continue;
            entries.append({file, desktop.value(QStringLiteral("Name")).toString(), mimeTypes});
        }
    }
    return entries;
}

} // namespace

// #region ── lifecycle ───────────────────────────────────────────────────────────────────────

System::System(QObject *parent)
    : QObject(parent)
{
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &System::readClipboard);
    readClipboard();
    connect(qApp, &QCoreApplication::aboutToQuit, this, &System::handClipboardOver);
    // GNOME's switch is the one the GTK side of this desktop already honours, so the app follows it rather than inventing a second one.
    QProcess gsettings;
    gsettings.start(QStringLiteral("gsettings"), {QStringLiteral("get"), QStringLiteral("org.gnome.desktop.interface"), QStringLiteral("enable-animations")});
    if (gsettings.waitForFinished(600))
        m_prefersReducedMotion = gsettings.readAllStandardOutput().trimmed() == "false";
}

void System::setInitialPath(const QString &path)
{
    g_initialPath = path;
}

QString System::homePath() const
{
    return QDir::homePath();
}

QString System::initialPath() const
{
    return g_initialPath;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── launching ───────────────────────────────────────────────────────────────────────

void System::open(const QString &path)
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

bool System::isMedia(const QString &path) const
{
    const QString name = QMimeDatabase().mimeTypeForFile(path, QMimeDatabase::MatchExtension).name();
    return name.startsWith(QLatin1String("image/")) || name.startsWith(QLatin1String("video/"));
}

void System::openMedia(const QString &path, const QStringList &siblings)
{
    // The gallery is asked by name; D-Bus starts it when it is installed and not running, and one already open takes the photo.
    const QString service = QStringLiteral("org.vados.Gallery");
    QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusConnectionInterface *registry = bus.isConnected() ? bus.interface() : nullptr;
    const bool isRunning = registry && registry->isServiceRegistered(service);
    const bool isActivatable = registry && registry->activatableServiceNames().value().contains(service);
    if (!isRunning && !isActivatable) {
        open(path);
        return;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(service, QStringLiteral("/org/vados/Gallery"), service, QStringLiteral("Open"));
    call << path << siblings;
    bus.asyncCall(call, 8000);
}

QVariantList System::applicationsFor(const QString &path) const
{
    const QMimeDatabase mimeDatabase;
    const QMimeType mimeType = mimeDatabase.mimeTypeForFile(path);
    QStringList accepted = {mimeType.name()};
    accepted.append(mimeType.allAncestors());

    QProcess query;
    query.start(QStringLiteral("xdg-mime"), {QStringLiteral("query"), QStringLiteral("default"), mimeType.name()});
    const QString defaultId = query.waitForFinished(800) ? QString::fromUtf8(query.readAllStandardOutput()).trimmed() : QString();

    QVariantList applications;
    QVariantMap defaultApplication;
    for (const DesktopEntry &entry : readDesktopEntries()) {
        bool isMatch = false;
        for (const QString &type : entry.mimeTypes)
            isMatch = isMatch || accepted.contains(type);
        if (!isMatch)
            continue;
        const QVariantMap application = {{QStringLiteral("name"), entry.name}, {QStringLiteral("file"), entry.file},
                                         {QStringLiteral("isDefault"), QFileInfo(entry.file).fileName() == defaultId}};
        if (QFileInfo(entry.file).fileName() == defaultId)
            defaultApplication = application;
        else
            applications.append(application);
    }
    std::sort(applications.begin(), applications.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap().value(QStringLiteral("name")).toString().compare(right.toMap().value(QStringLiteral("name")).toString(), Qt::CaseInsensitive) < 0;
    });
    if (!defaultApplication.isEmpty())
        applications.prepend(defaultApplication);
    return applications;
}

void System::openWith(const QString &desktopFile, const QStringList &paths)
{
    QProcess::startDetached(QStringLiteral("gio"), QStringList{QStringLiteral("launch"), desktopFile} + paths);
}

void System::openTerminal(const QString &directory, const QString &command)
{
    QString program = command.trimmed();
    if (program.isEmpty())
        program = qEnvironmentVariable("TERMINAL");
    for (const QString &candidate : {QStringLiteral("foot"), QStringLiteral("kitty"), QStringLiteral("alacritty"), QStringLiteral("wezterm"), QStringLiteral("konsole")}) {
        if (!program.isEmpty())
            break;
        if (!QStandardPaths::findExecutable(candidate).isEmpty())
            program = candidate;
    }
    // Every terminal opens its shell in the directory it was started from, so the working directory is the one argument that needs no per-terminal flag.
    QStringList arguments = QProcess::splitCommand(program);
    if (arguments.isEmpty())
        return;
    const QString executable = arguments.takeFirst();
    QProcess::startDetached(executable, arguments, directory);
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── clipboard and drag ──────────────────────────────────────────────────────────────

void System::copyPaths(const QStringList &paths, bool isCut)
{
    auto *mimeData = new QMimeData;
    QList<QUrl> urls;
    QByteArray gnomeList = isCut ? "cut" : "copy";
    for (const QString &path : paths) {
        const QUrl url = QUrl::fromLocalFile(path);
        urls.append(url);
        gnomeList += '\n' + url.toEncoded();
    }
    mimeData->setUrls(urls);
    mimeData->setText(paths.join(QLatin1Char('\n')));
    // Both dialects of "this was cut", so a paste in Nautilus, Thunar, Nemo or Dolphin moves rather than copies.
    mimeData->setData(GNOME_COPIED_FILES, gnomeList);
    mimeData->setData(KDE_CUT_SELECTION, isCut ? "1" : "0");
    QGuiApplication::clipboard()->setMimeData(mimeData);
}

// On Wayland the clipboard lives in the app that set it, so closing the window empties it. wl-copy stays behind as the owner.
void System::handClipboardOver()
{
    if (m_clipboardPaths.isEmpty() || !QGuiApplication::clipboard()->ownsClipboard())
        return;
    const QString program = QStandardPaths::findExecutable(QStringLiteral("wl-copy"));
    if (program.isEmpty())
        return;
    QByteArray body;
    QString type = QStringLiteral("text/uri-list");
    if (m_isClipboardCut) {
        type = GNOME_COPIED_FILES;
        body = "cut";
    }
    for (const QString &path : m_clipboardPaths) {
        const QByteArray url = QUrl::fromLocalFile(path).toEncoded();
        body += m_isClipboardCut ? '\n' + url : url + "\r\n";
    }
    QProcess process;
    process.start(program, {QStringLiteral("--type"), type});
    if (!process.waitForStarted(500))
        return;
    process.write(body);
    process.closeWriteChannel();
    process.waitForFinished(1500);
}

void System::copyText(const QString &text)
{
    QGuiApplication::clipboard()->setText(text);
}

void System::clearClipboard()
{
    QGuiApplication::clipboard()->clear();
}

void System::readClipboard()
{
    const QMimeData *mimeData = QGuiApplication::clipboard()->mimeData();
    QStringList paths;
    bool isCut = false;
    if (mimeData) {
        if (mimeData->hasFormat(GNOME_COPIED_FILES)) {
            const QList<QByteArray> lines = mimeData->data(GNOME_COPIED_FILES).split('\n');
            isCut = !lines.isEmpty() && lines.first().trimmed() == "cut";
            for (int index = 1; index < lines.size(); ++index) {
                const QUrl url = QUrl::fromEncoded(lines.at(index).trimmed());
                if (url.isLocalFile())
                    paths.append(url.toLocalFile());
            }
        } else if (mimeData->hasUrls()) {
            isCut = mimeData->data(KDE_CUT_SELECTION) == "1";
            for (const QUrl &url : mimeData->urls())
                if (url.isLocalFile())
                    paths.append(url.toLocalFile());
        }
    }
    if (paths == m_clipboardPaths && isCut == m_isClipboardCut)
        return;
    m_clipboardPaths = paths;
    m_isClipboardCut = isCut;
    emit clipboardChanged();
}

int System::startDrag(const QStringList &paths, const QVariant &picture, int hotX, int hotY)
{
    auto *mimeData = new QMimeData;
    QList<QUrl> urls;
    for (const QString &path : paths)
        urls.append(QUrl::fromLocalFile(path));
    mimeData->setUrls(urls);
    auto *drag = new QDrag(this);
    drag->setMimeData(mimeData);
    // The picture may not be ready yet if the pointer outran the grab; the drag goes ahead without one rather than waiting.
    const QImage image = picture.value<QImage>();
    if (!image.isNull()) {
        drag->setPixmap(QPixmap::fromImage(image));
        drag->setHotSpot(QPoint(hotX, hotY));
    }
    const Qt::DropAction action = drag->exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction, Qt::CopyAction);
    drag->deleteLater();
    return int(action);
}

int System::keyboardModifiers() const
{
    return int(QGuiApplication::queryKeyboardModifiers());
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── facts about files ───────────────────────────────────────────────────────────────

QString System::expandPath(const QString &text) const
{
    QString path = text.trimmed();
    if (path == QLatin1String("~"))
        return QDir::homePath();
    if (path.startsWith(QLatin1String("~/")))
        path = QDir::homePath() + path.mid(1);
    if (path.startsWith(QLatin1String("file://")))
        path = QUrl(path).toLocalFile();
    return path == QLatin1String("trash:///") ? path : QDir::cleanPath(path);
}

QStringList System::completePath(const QString &text) const
{
    const QString expanded = text.trimmed().startsWith(QLatin1Char('~')) ? QDir::homePath() + text.trimmed().mid(1) : text.trimmed();
    if (!expanded.startsWith(QLatin1Char('/')))
        return {};
    const QString parent = expanded.endsWith(QLatin1Char('/')) ? expanded : QFileInfo(expanded).absolutePath();
    const QString prefix = expanded.endsWith(QLatin1Char('/')) ? QString() : QFileInfo(expanded).fileName();
    QStringList matches;
    const QFileInfoList children = QDir(parent).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | (prefix.startsWith(QLatin1Char('.')) ? QDir::Hidden : QDir::Filter(0)), QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &child : children) {
        if (child.fileName().startsWith(prefix, Qt::CaseInsensitive))
            matches.append(child.absoluteFilePath());
        if (matches.size() >= 8)
            break;
    }
    return matches;
}

QVariantMap System::details(const QString &path) const
{
    const QFileInfo info(path);
    const QMimeDatabase mimeDatabase;
    const QMimeType mimeType = mimeDatabase.mimeTypeForFile(info);
    auto permissionText = [&info] {
        const QFile::Permissions permissions = info.permissions();
        QString text;
        text += permissions & QFile::ReadOwner ? 'r' : '-';
        text += permissions & QFile::WriteOwner ? 'w' : '-';
        text += permissions & QFile::ExeOwner ? 'x' : '-';
        text += permissions & QFile::ReadGroup ? 'r' : '-';
        text += permissions & QFile::WriteGroup ? 'w' : '-';
        text += permissions & QFile::ExeGroup ? 'x' : '-';
        text += permissions & QFile::ReadOther ? 'r' : '-';
        text += permissions & QFile::WriteOther ? 'w' : '-';
        text += permissions & QFile::ExeOther ? 'x' : '-';
        return text;
    };
    const QLocale locale = QLocale::c();
    const QString dateFormat = QStringLiteral("d MMM yyyy, HH:mm");
    return {
        {QStringLiteral("name"), info.fileName().isEmpty() ? path : info.fileName()},
        {QStringLiteral("path"), info.absoluteFilePath()},
        {QStringLiteral("parent"), info.absolutePath()},
        {QStringLiteral("kindText"), mimeType.comment()},
        {QStringLiteral("mimeType"), mimeType.name()},
        {QStringLiteral("size"), info.isDir() ? -1 : info.size()},
        {QStringLiteral("sizeText"), info.isDir() ? QString() : formatSize(info.size())},
        {QStringLiteral("modifiedText"), locale.toString(info.lastModified(), dateFormat)},
        {QStringLiteral("createdText"), info.birthTime().isValid() ? locale.toString(info.birthTime(), dateFormat) : QString()},
        {QStringLiteral("accessedText"), locale.toString(info.lastRead(), dateFormat)},
        {QStringLiteral("permissions"), permissionText()},
        {QStringLiteral("owner"), info.owner()},
        {QStringLiteral("group"), info.group()},
        {QStringLiteral("linkTarget"), info.isSymLink() ? info.symLinkTarget() : QString()},
        {QStringLiteral("isDirectory"), info.isDir()},
        {QStringLiteral("isWritable"), info.isWritable()},
    };
}

QString System::textPreview(const QString &path, int maximumBytes) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    const QByteArray bytes = file.read(maximumBytes);
    // A NUL in the first block is the cheapest honest test for "this is not text"; rendering a binary as glyphs is noise.
    if (bytes.contains('\0'))
        return QString();
    QStringDecoder decoder(QStringDecoder::Utf8);
    const QString text = decoder(bytes);
    return decoder.hasError() ? QString() : text;
}

void System::measureFolder(const QString &path)
{
    // A new question cancels the walk still answering the old one, so clicking through folders never stacks up disk scans.
    if (m_measureCancel)
        m_measureCancel->store(true);
    auto isCancelled = std::make_shared<std::atomic_bool>(false);
    m_measureCancel = isCancelled;
    QPointer<System> guard(this);
    auto future = QtConcurrent::run([path, isCancelled] {
        qint64 bytes = 0;
        int files = 0;
        int folders = 0;
        QDirIterator iterator(path, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System | QDir::NoSymLinks, QDirIterator::Subdirectories);
        while (iterator.hasNext() && !isCancelled->load()) {
            iterator.next();
            const QFileInfo info = iterator.fileInfo();
            if (info.isDir()) {
                ++folders;
            } else {
                ++files;
                bytes += info.size();
            }
        }
        return std::make_tuple(bytes, files, folders);
    });
    future.then(this, [guard, path, isCancelled](std::tuple<qint64, int, int> result) {
        if (guard && !isCancelled->load())
            emit guard->folderMeasured(path, std::get<0>(result), std::get<1>(result), std::get<2>(result));
    });
}

bool System::exists(const QString &path) const
{
    return path == QLatin1String("trash:///") || QFileInfo::exists(path);
}

bool System::isDirectory(const QString &path) const
{
    return QFileInfo(path).isDir();
}

bool System::isWritable(const QString &path) const
{
    return QFileInfo(path).isWritable();
}

QString System::parentOf(const QString &path) const
{
    if (path == QLatin1String("/") || path == QLatin1String("trash:///"))
        return QString();
    return QFileInfo(path).absolutePath();
}

QString System::nameOf(const QString &path) const
{
    if (path == QLatin1String("/"))
        return QStringLiteral("System");
    if (path == QLatin1String("trash:///"))
        return QStringLiteral("Trash");
    if (path == QDir::homePath())
        return QStringLiteral("Home");
    return QFileInfo(path).fileName();
}

QString System::formatSize(qint64 bytes) const
{
    return QLocale::c().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

QStringList System::localPaths(const QVariantList &urls) const
{
    QStringList paths;
    for (const QVariant &value : urls) {
        const QUrl url = value.toUrl();
        if (url.isLocalFile())
            paths.append(QDir::cleanPath(url.toLocalFile()));
    }
    return paths;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
