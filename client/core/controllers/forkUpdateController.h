#ifndef FORKUPDATECONTROLLER_H
#define FORKUPDATECONTROLLER_H

#include "core/controllers/updateController.h"

// Update source for the Cheburnezia fork: the latest GitHub release of
// CHEBURNEZIA_UPDATE_REPO instead of Amnezia's gateway. Releases are published
// by deploy/release_android.sh with tags v<upstream version>-ch<N>; a release
// is newer when its N is greater than CHEBURNEZIA_BUILD of this build.
class ForkUpdateController : public UpdateController
{
    Q_OBJECT
public:
    explicit ForkUpdateController(SecureAppSettingsRepository* appSettingsRepository, QObject *parent = nullptr);

    // The fork is never installed from a store, even when Android reports Play.
    bool isStoreUpdate() const override;

    static int currentBuild();
    static int buildFromTag(const QString &tag);

public slots:
    void checkForUpdates() override;
    // Opens the release asset for this platform (the APK on Android) in the
    // browser; the system installer takes over from the download.
    void startUpdate() override;

private:
    void handleReleaseReply(const QByteArray &data);
};

#endif // FORKUPDATECONTROLLER_H
