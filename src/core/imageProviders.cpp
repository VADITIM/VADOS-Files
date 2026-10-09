#include "imageProviders.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QProcess>
#include <QRunnable>
#include <QStandardPaths>
#include <QSvgRenderer>
#include <QUrl>
#include <QUrlQuery>

namespace {

constexpr int LARGE_EDGE = 256;

QString thumbnailRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/thumbnails");
}

QImage readCached(const QString &cachePath, qint64 modifiedSeconds)
{
    QImageReader reader(cachePath);
    if (!reader.canRead())
        return {};
    // A thumbnail older than its file is a picture of something that is no longer there.
    if (reader.text(QStringLiteral("Thumb::MTime")).toLongLong() != modifiedSeconds)
        return {};
    return reader.read();
}

QImage generate(const QString &path, const QString &uri, qint64 modifiedSeconds, const QString &cachePath)
{
    QImage image;
    QImageReader reader(path);
    reader.setAutoTransform(true);
    if (reader.canRead()) {
        const QSize original = reader.size();
        if (original.isValid() && (original.width() > LARGE_EDGE || original.height() > LARGE_EDGE))
            reader.setScaledSize(original.scaled(LARGE_EDGE, LARGE_EDGE, Qt::KeepAspectRatio));
        image = reader.read();
    } else {
        const QString thumbnailer = QStandardPaths::findExecutable(QStringLiteral("ffmpegthumbnailer"));
        if (thumbnailer.isEmpty())
            return {};
        QDir().mkpath(QFileInfo(cachePath).absolutePath());
        const QString temporary = cachePath + QStringLiteral(".part.png");
        QProcess process;
        process.start(thumbnailer, {QStringLiteral("-i"), path, QStringLiteral("-o"), temporary, QStringLiteral("-s"), QString::number(LARGE_EDGE), QStringLiteral("-c"), QStringLiteral("png")});
        if (!process.waitForFinished(8000) || process.exitCode() != 0) {
            QFile::remove(temporary);
            return {};
        }
        image.load(temporary);
        QFile::remove(temporary);
    }
    if (image.isNull())
        return {};
    image.setText(QStringLiteral("Thumb::URI"), uri);
    image.setText(QStringLiteral("Thumb::MTime"), QString::number(modifiedSeconds));
    image.setText(QStringLiteral("Thumb::Size"), QString::number(QFileInfo(path).size()));
    QDir().mkpath(QFileInfo(cachePath).absolutePath());
    const QString temporary = cachePath + QStringLiteral(".tmp");
    if (image.save(temporary, "PNG")) {
        QFile::setPermissions(temporary, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        QFile::remove(cachePath);
        QFile::rename(temporary, cachePath);
    }
    return image;
}

class ThumbnailResponse : public QQuickImageResponse, public QRunnable {
public:
    ThumbnailResponse(QString path, QSize requestedSize)
        : m_path(std::move(path))
        , m_requestedSize(requestedSize)
    {
        setAutoDelete(false);
    }

    QQuickTextureFactory *textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(m_image); }
    QString errorString() const override { return m_image.isNull() ? QStringLiteral("no thumbnail") : QString(); }

    void run() override
    {
        const QFileInfo info(m_path);
        if (info.exists() && !m_path.startsWith(thumbnailRoot())) {
            const QString uri = QString::fromUtf8(QUrl::fromLocalFile(m_path).toEncoded());
            const QString hash = QString::fromLatin1(QCryptographicHash::hash(uri.toUtf8(), QCryptographicHash::Md5).toHex());
            const qint64 modifiedSeconds = info.lastModified().toSecsSinceEpoch();
            for (const QString &bucket : {QStringLiteral("large"), QStringLiteral("x-large"), QStringLiteral("normal")}) {
                m_image = readCached(thumbnailRoot() + QLatin1Char('/') + bucket + QLatin1Char('/') + hash + QStringLiteral(".png"), modifiedSeconds);
                if (!m_image.isNull())
                    break;
            }
            if (m_image.isNull())
                m_image = generate(m_path, uri, modifiedSeconds, thumbnailRoot() + QStringLiteral("/large/") + hash + QStringLiteral(".png"));
            if (!m_image.isNull() && m_requestedSize.isValid() && (m_image.width() > m_requestedSize.width() * 1.5 || m_image.height() > m_requestedSize.height() * 1.5))
                m_image = m_image.scaled(m_requestedSize, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        }
        emit finished();
    }

private:
    QString m_path;
    QSize m_requestedSize;
    QImage m_image;
};

} // namespace

// #region ── thumbnails ──────────────────────────────────────────────────────────────────────

ThumbnailProvider::ThumbnailProvider()
{
    // Decoding is disk- and CPU-bound; a handful at once keeps a fast scroll from queueing hundreds of decodes behind the ones in view.
    m_pool.setMaxThreadCount(qMax(2, QThread::idealThreadCount() / 2));
}

QQuickImageResponse *ThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new ThumbnailResponse(QUrl::fromPercentEncoding(id.toUtf8()), requestedSize);
    m_pool.start(response);
    return response;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── glyphs ──────────────────────────────────────────────────────────────────────────

GlyphProvider::GlyphProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage GlyphProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QString name = id.section(QLatin1Char('?'), 0, 0);
    const QUrlQuery query(id.section(QLatin1Char('?'), 1));
    const QString ink = QLatin1Char('#') + query.queryItemValue(QStringLiteral("ink"));
    QFile file(QStringLiteral(":/qt/qml/Vados/assets/glyphs/%1.svg").arg(name));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QByteArray svg = file.readAll();
    svg.replace("currentColor", ink.toUtf8());
    QSvgRenderer renderer(svg);
    // A glyph laid out before its size is known asks for 0×0; it gets a default size rather than a null image.
    const QSize target = requestedSize.width() > 0 && requestedSize.height() > 0 ? requestedSize : QSize(48, 48);
    QImage image(target, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    renderer.render(&painter);
    painter.end();
    if (size)
        *size = target;
    return image;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
