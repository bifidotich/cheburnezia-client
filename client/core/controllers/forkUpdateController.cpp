#include "forkUpdateController.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>

#include "amneziaApplication.h"
#include "logger.h"
#include "version.h"

namespace
{
    Logger logger("ForkUpdateController");

    // Suffix of the APK asset built for this ABI, see deploy/release_android.sh.
#if defined(Q_OS_ANDROID)
#  if defined(Q_PROCESSOR_ARM_64)
    constexpr QLatin1String kAssetSuffix("-arm64-v8a.apk");
#  elif defined(Q_PROCESSOR_ARM)
    constexpr QLatin1String kAssetSuffix("-armeabi-v7a.apk");
#  elif defined(Q_PROCESSOR_X86_64)
    constexpr QLatin1String kAssetSuffix("-x86_64.apk");
#  else
    constexpr QLatin1String kAssetSuffix("-x86.apk");
#  endif
#endif
}

ForkUpdateController::ForkUpdateController(SecureAppSettingsRepository* appSettingsRepository, QObject *parent)
    : UpdateController(appSettingsRepository, parent)
{
}

QString ForkUpdateController::getRawChangelogText() const
{
    return m_changelogText;
}

QString ForkUpdateController::getReleaseDate() const
{
    return m_releaseDate;
}

QString ForkUpdateController::getVersion() const
{
    return m_version;
}

int ForkUpdateController::currentBuild()
{
    return QString(CHEBURNEZIA_BUILD).toInt();
}

int ForkUpdateController::buildFromTag(const QString &tag)
{
    static const QRegularExpression re(QStringLiteral("-ch(\\d+)$"));
    const auto match = re.match(tag);
    return match.hasMatch() ? match.captured(1).toInt() : -1;
}

void ForkUpdateController::checkForUpdates()
{
    if (m_checkRunning) {
        return;
    }
    m_checkRunning = true;

    const QUrl url(QStringLiteral("https://api.github.com/repos/%1/releases/latest").arg(CHEBURNEZIA_UPDATE_REPO));

    QNetworkRequest req(url);
    req.setTransferTimeout(10000);
    req.setRawHeader("Accept", "application/vnd.github+json");
    // GitHub API rejects requests without a User-Agent.
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("Cheburnezia/%1-ch%2").arg(APP_VERSION).arg(currentBuild()));

    QNetworkReply *reply = amnApp->networkManager()->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_checkRunning = false;

        if (reply->error() != QNetworkReply::NoError) {
            logger.error() << "Release check failed:" << reply->errorString() << "HTTP status:"
                           << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            emit updateCheckFailed();
            return;
        }
        handleReleaseReply(reply->readAll());
    });
}

void ForkUpdateController::handleReleaseReply(const QByteArray &data)
{
    const QJsonObject release = QJsonDocument::fromJson(data).object();
    const QString tag = release.value("tag_name").toString();
    const int remoteBuild = buildFromTag(tag);
    if (remoteBuild < 0) {
        logger.error() << "Unexpected release tag:" << tag;
        emit updateCheckFailed();
        return;
    }

    logger.info() << "Latest release" << tag << "current build" << currentBuild();
    if (remoteBuild <= currentBuild()) {
        emit noUpdateFound();
        return;
    }

    m_version = tag.startsWith('v') ? tag.mid(1) : tag;
    m_changelogText = release.value("body").toString();
    m_releaseDate = QDateTime::fromString(release.value("published_at").toString(), Qt::ISODate)
                            .toLocalTime().date().toString(Qt::ISODate);

    // Without an asset for this platform the release page is the best we can offer.
    m_downloadUrl = release.value("html_url").toString();
#if defined(Q_OS_ANDROID)
    for (const QJsonValue &asset : release.value("assets").toArray()) {
        const QJsonObject obj = asset.toObject();
        if (obj.value("name").toString().endsWith(kAssetSuffix)) {
            m_downloadUrl = obj.value("browser_download_url").toString();
            break;
        }
    }
#endif

    emit updateFound();
}

void ForkUpdateController::runInstaller()
{
    if (m_downloadUrl.isEmpty()) {
        logger.error() << "Download URL is empty";
        return;
    }
    QDesktopServices::openUrl(QUrl(m_downloadUrl));
}
