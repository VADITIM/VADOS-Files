#include "portalService.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMimeDatabase>
#include <QProcess>
#include <QUrl>

namespace {

// The portal's filter shape: a name and its rules, each rule a glob (0) or a MIME type (1).
struct FilterRule {
    uint type = 0;
    QString pattern;
};

struct Filter {
    QString name;
    QList<FilterRule> rules;
};

} // namespace

Q_DECLARE_METATYPE(FilterRule)
Q_DECLARE_METATYPE(Filter)

QDBusArgument &operator<<(QDBusArgument &argument, const FilterRule &rule)
{
    argument.beginStructure();
    argument << rule.type << rule.pattern;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, FilterRule &rule)
{
    argument.beginStructure();
    argument >> rule.type >> rule.pattern;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const Filter &filter)
{
    argument.beginStructure();
    argument << filter.name << filter.rules;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, Filter &filter)
{
    argument.beginStructure();
    argument >> filter.name >> filter.rules;
    argument.endStructure();
    return argument;
}

namespace {

const QString OBJECT_PATH = QStringLiteral("/org/freedesktop/portal/desktop");
const QString SERVICE_NAME = QStringLiteral("org.freedesktop.impl.portal.desktop.vados");

enum Response : uint { Success = 0, Cancelled = 1, Failed = 2 };

QList<Filter> filtersFrom(const QVariant &value)
{
    if (!value.canConvert<QDBusArgument>())
        return {};
    return qdbus_cast<QList<Filter>>(value.value<QDBusArgument>());
}

// The picker only filters by name, so a MIME rule is turned into the globs that MIME type is known by.
QJsonArray globsFor(const Filter &filter)
{
    static const QMimeDatabase database;
    QJsonArray globs;
    for (const FilterRule &rule : filter.rules) {
        if (rule.type == 0) {
            globs.append(rule.pattern);
            continue;
        }
        if (rule.pattern.endsWith(QLatin1String("/*"))) {
            const QString prefix = rule.pattern.chopped(1);
            for (const QMimeType &type : database.allMimeTypes())
                if (type.name().startsWith(prefix))
                    for (const QString &glob : type.globPatterns())
                        globs.append(glob);
            continue;
        }
        for (const QString &glob : database.mimeTypeForName(rule.pattern).globPatterns())
            globs.append(glob);
    }
    return globs;
}

// Byte-string paths arrive NUL-terminated.
QString pathFrom(const QVariant &value)
{
    QByteArray bytes = value.toByteArray();
    while (bytes.endsWith('\0'))
        bytes.chop(1);
    return QFile::decodeName(bytes);
}

QJsonObject requestFor(const QString &mode, const QString &title, const QVariantMap &options)
{
    QJsonObject request;
    request.insert(QStringLiteral("mode"), mode);
    request.insert(QStringLiteral("title"), title);
    request.insert(QStringLiteral("acceptLabel"), options.value(QStringLiteral("accept_label")).toString());
    request.insert(QStringLiteral("multiple"), options.value(QStringLiteral("multiple")).toBool());

    const QList<Filter> filters = filtersFrom(options.value(QStringLiteral("filters")));
    QJsonArray filterList;
    for (const Filter &filter : filters)
        filterList.append(QJsonObject{{QStringLiteral("name"), filter.name}, {QStringLiteral("patterns"), globsFor(filter)}});
    request.insert(QStringLiteral("filters"), filterList);
    if (options.contains(QStringLiteral("current_filter"))) {
        const Filter current = qdbus_cast<Filter>(options.value(QStringLiteral("current_filter")).value<QDBusArgument>());
        for (int index = 0; index < filters.size(); ++index)
            if (filters.at(index).name == current.name)
                request.insert(QStringLiteral("filter"), index);
    }

    QString folder = pathFrom(options.value(QStringLiteral("current_folder")));
    const QString file = pathFrom(options.value(QStringLiteral("current_file")));
    if (!file.isEmpty()) {
        folder = QFileInfo(file).absolutePath();
        request.insert(QStringLiteral("name"), QFileInfo(file).fileName());
    }
    if (options.contains(QStringLiteral("current_name")))
        request.insert(QStringLiteral("name"), options.value(QStringLiteral("current_name")).toString());
    if (!folder.isEmpty() && QFileInfo(folder).isDir())
        request.insert(QStringLiteral("folder"), folder);
    return request;
}

} // namespace

PortalService::PortalService(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
}

int PortalService::run(int argumentCount, char *argumentValues[])
{
    QCoreApplication application(argumentCount, argumentValues);
    qDBusRegisterMetaType<FilterRule>();
    qDBusRegisterMetaType<QList<FilterRule>>();
    qDBusRegisterMetaType<Filter>();
    qDBusRegisterMetaType<QList<Filter>>();
    QObject root;
    new PortalService(&root);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(OBJECT_PATH, &root) || !bus.registerService(SERVICE_NAME))
        return 1;
    return application.exec();
}

void PortalService::OpenFile(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title, const QVariantMap &options, const QDBusMessage &message)
{
    const bool isFolder = options.value(QStringLiteral("directory")).toBool();
    ask(handle, requestFor(isFolder ? QStringLiteral("folder") : QStringLiteral("open"), title, options), options, {}, message);
}

void PortalService::SaveFile(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title, const QVariantMap &options, const QDBusMessage &message)
{
    ask(handle, requestFor(QStringLiteral("save"), title, options), options, {}, message);
}

void PortalService::SaveFiles(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title, const QVariantMap &options, const QDBusMessage &message)
{
    QStringList names;
    const QVariant files = options.value(QStringLiteral("files"));
    const QByteArrayList fileNames = files.canConvert<QDBusArgument>() ? qdbus_cast<QByteArrayList>(files.value<QDBusArgument>()) : files.value<QByteArrayList>();
    {
        for (const QByteArray &name : fileNames) {
            QByteArray bytes = name;
            while (bytes.endsWith('\0'))
                bytes.chop(1);
            names.append(QFile::decodeName(bytes));
        }
    }
    QJsonObject request = requestFor(QStringLiteral("folder"), title, options);
    if (request.value(QStringLiteral("acceptLabel")).toString().isEmpty())
        request.insert(QStringLiteral("acceptLabel"), QStringLiteral("Save here"));
    ask(handle, request, options, names.isEmpty() ? QStringList{QString()} : names, message);
}

void PortalService::ask(const QDBusObjectPath &handle, const QJsonObject &request, const QVariantMap &options, const QStringList &names, const QDBusMessage &message)
{
    message.setDelayedReply(true);
    QDBusConnection bus = QDBusConnection::sessionBus();

    auto *process = new QProcess(this);
    process->setProgram(QCoreApplication::applicationFilePath());
    process->setArguments({QStringLiteral("--pick"), QString::fromUtf8(QJsonDocument(request).toJson(QJsonDocument::Compact))});
    process->setProcessChannelMode(QProcess::SeparateChannels);

    auto *requestObject = new QObject(process);
    new PortalRequest(requestObject, process);
    const bool hasRequest = bus.registerObject(handle.path(), requestObject);

    const QList<Filter> filters = filtersFrom(options.value(QStringLiteral("filters")));
    connect(process, &QProcess::finished, this, [process, message, names, filters, handle, hasRequest](int exitCode, QProcess::ExitStatus status) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (hasRequest)
            bus.unregisterObject(handle.path());
        QStringList uris;
        int filterIndex = -1;
        for (const QByteArray &line : process->readAllStandardOutput().split('\n')) {
            if (line.startsWith("filter "))
                filterIndex = line.mid(7).toInt();
            else if (!line.isEmpty())
                uris.append(QString::fromUtf8(line));
        }
        QVariantMap results;
        uint response = Cancelled;
        if (status == QProcess::NormalExit && exitCode == 0 && !uris.isEmpty()) {
            response = Success;
            if (names.isEmpty()) {
                results.insert(QStringLiteral("uris"), uris);
            } else {
                // SaveFiles: the picked folder, with each of the asked-for names inside it.
                const QString folder = QUrl(uris.first()).toLocalFile();
                QStringList joined;
                for (const QString &name : names)
                    joined.append(QUrl::fromLocalFile(name.isEmpty() ? folder : QDir(folder).filePath(name)).toString(QUrl::FullyEncoded));
                results.insert(QStringLiteral("uris"), joined);
            }
            if (filterIndex >= 0 && filterIndex < filters.size())
                results.insert(QStringLiteral("current_filter"), QVariant::fromValue(filters.at(filterIndex)));
        }
        bus.send(message.createReply({response, results}));
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [process, message, handle, hasRequest](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (hasRequest)
            bus.unregisterObject(handle.path());
        bus.send(message.createReply({uint(Failed), QVariantMap()}));
        process->deleteLater();
    });
    process->start();
}

PortalRequest::PortalRequest(QObject *parent, QProcess *process)
    : QDBusAbstractAdaptor(parent)
    , m_process(process)
{
}

void PortalRequest::Close()
{
    m_process->terminate();
}
