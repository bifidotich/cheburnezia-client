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
#include "core/utils/appUiConfig.h"
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

bool ForkUpdateController::isStoreUpdate() const
{
    return false;
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
#if !CLIENT_ENABLE_APP_UPDATES
    return;
#endif

    if (isUpdateCheckRunning()) {
        return;
    }
    setUpdateCheckRunning(true);

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
        setUpdateCheckRunning(false);

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
        emit updateNotFound();
        return;
    }

    m_version = tag.startsWith('v') ? tag.mid(1) : tag;
    m_releaseDate = QDateTime::fromString(release.value("published_at").toString(), Qt::ISODate)
                            .toLocalTime().date().toString(Qt::ISODate);

    // Release notes are Markdown: list items go to the changelog sections by their
    // conventional-commit prefix, the remaining prose becomes the description.
    static const QRegularExpression bulletRe(QStringLiteral("^\\s*[-*]\\s+(.*)$"));
    static const QRegularExpression prefixRe(QStringLiteral("^(\\w+)(\\([^)]*\\))?!?:\\s*"));
    // "--generate-notes" appends " by @author in <PR url>" to every item.
    static const QRegularExpression authorRe(QStringLiteral("\\s+by @\\S+ in \\S+$"));

    QStringList description;
    m_newFeatures.clear();
    m_improvements.clear();
    m_bugFixes.clear();
    m_tags.clear();
    const QStringList lines = release.value("body").toString().split('\n');
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith('#') || line.startsWith(QLatin1String("**Full Changelog**"))) {
            continue;
        }

        const auto bullet = bulletRe.match(line);
        if (!bullet.hasMatch()) {
            description.append(line);
            continue;
        }

        QString item = bullet.captured(1);
        item.remove(authorRe);
        const auto prefix = prefixRe.match(item);
        const QString type = prefix.hasMatch() ? prefix.captured(1).toLower() : QString();
        if (prefix.hasMatch()) {
            item = item.mid(prefix.capturedLength());
        }
        if (item.isEmpty()) {
            continue;
        }
        item[0] = item[0].toUpper();

        if (type == QLatin1String("feat")) {
            m_newFeatures.append(item);
        } else if (type == QLatin1String("fix")) {
            m_bugFixes.append(item);
        } else {
            m_improvements.append(item);
        }
    }
    m_description = description.join('\n');

    // Without an asset for this platform the release page is the best we can offer.
    m_releasePageUrl = release.value("html_url").toString();
#if defined(Q_OS_ANDROID)
    for (const QJsonValue &asset : release.value("assets").toArray()) {
        const QJsonObject obj = asset.toObject();
        if (obj.value("name").toString().endsWith(kAssetSuffix)) {
            m_releasePageUrl = obj.value("browser_download_url").toString();
            break;
        }
    }
#endif

    setUpdateState(UpdateState::State::Idle);
    emit updateFound();
}

void ForkUpdateController::startUpdate()
{
    if (m_releasePageUrl.isEmpty()) {
        logger.error() << "Download URL is empty";
        setUpdateState(UpdateState::State::DownloadError);
        return;
    }
    QDesktopServices::openUrl(QUrl(m_releasePageUrl));
}
