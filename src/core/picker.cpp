#include "picker.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrl>

#include <cstdio>

namespace {

QJsonObject g_request;

} // namespace

Picker::Picker(QObject *parent)
    : QObject(parent)
{
}

QString Picker::configure(const QByteArray &request)
{
    g_request = QJsonDocument::fromJson(request).object();
    if (g_request.isEmpty())
        g_request.insert(QStringLiteral("mode"), QStringLiteral("open"));
    return g_request.value(QStringLiteral("folder")).toString();
}

bool Picker::isActive() const
{
    return !g_request.isEmpty();
}

QString Picker::mode() const
{
    return g_request.value(QStringLiteral("mode")).toString(QStringLiteral("open"));
}

QString Picker::title() const
{
    return g_request.value(QStringLiteral("title")).toString();
}

QString Picker::acceptLabel() const
{
    QString label = g_request.value(QStringLiteral("acceptLabel")).toString();
    if (!label.isEmpty())
        return label.remove(QLatin1Char('_'));
    return mode() == QLatin1String("save") ? QStringLiteral("Save") : QStringLiteral("Select");
}

bool Picker::isMultiple() const
{
    return g_request.value(QStringLiteral("multiple")).toBool();
}

QString Picker::suggestedName() const
{
    return g_request.value(QStringLiteral("name")).toString();
}

QVariantList Picker::filters() const
{
    return g_request.value(QStringLiteral("filters")).toArray().toVariantList();
}

int Picker::initialFilter() const
{
    return g_request.value(QStringLiteral("filter")).toInt(0);
}

void Picker::accept(const QStringList &paths, int filterIndex)
{
    if (paths.isEmpty())
        return;
    // The first line names the filter in force, so the asking app can remember it; every line after is a file.
    std::printf("filter %d\n", filterIndex);
    for (const QString &path : paths)
        std::printf("%s\n", QUrl::fromLocalFile(path).toEncoded().constData());
    std::fflush(stdout);
    QCoreApplication::exit(0);
}

void Picker::cancel()
{
    QCoreApplication::exit(1);
}
