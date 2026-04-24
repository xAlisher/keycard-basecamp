// XPUB export proof test — runs WITHOUT logoscore/IPC
// Directly instantiates KeycardPlugin and exercises the full flow:
//   discoverReader → discoverCard → checkPairing → removeKey →
//   loadKey (BIP39 seed with chain code) → testXPUBExport
//
// Build: see tests/CMakeLists_xpub_proof.txt or build manually via nix develop
// Usage: ./xpub_proof <pin>
//   e.g.  ./xpub_proof 111111

#include <cstdio>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QDebug>

// Plugin lives in keycard-core/src — include directly
#include "../keycard-core/src/plugin.h"

static QJsonObject call(const QString& label, const QString& json)
{
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    QJsonObject obj   = doc.isObject() ? doc.object() : QJsonObject{};
    fprintf(stderr, "\n==== %s ====\n%s\n",
            label.toUtf8().constData(),
            QJsonDocument(obj).toJson(QJsonDocument::Indented).constData());
    fflush(stderr);
    return obj;
}

int main(int argc, char** argv)
{
    puts("xpub_proof: reached main()"); fflush(stdout);
    QCoreApplication app(argc, argv);
    puts("xpub_proof: QCoreApplication constructed"); fflush(stdout);
    QString pin = (argc >= 2) ? QString::fromUtf8(argv[1]) : "111111";
    puts("xpub_proof: pin set"); fflush(stdout);

    // BIP39 test seed (64 bytes): "abandon" x11 + "about", empty passphrase
    // Well-known BIP39 test vector — produces a real BIP32 master key with chain code.
    const QString TEST_SEED_HEX =
        "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"
        "9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4";

    KeycardPlugin plugin;
    plugin.initLogos(nullptr);  // safe: initLogos only stores the pointer

    // 1. Discover reader
    auto r1 = call("discoverReader", plugin.discoverReader());
    if (!r1.value("found").toBool()) {
        qCritical() << "FAIL: no reader";
        return 1;
    }

    // 2. Discover card
    auto r2 = call("discoverCard", plugin.discoverCard());
    if (!r2.value("found").toBool()) {
        qCritical() << "FAIL: no card";
        return 1;
    }

    // 3. Check pairing
    auto r3 = call("checkPairing", plugin.checkPairing());
    if (!r3.value("paired").toBool()) {
        qCritical() << "FAIL: not paired";
        return 1;
    }

    // 4. Authorize (open secure channel + verify PIN)
    auto r4 = call("authorize", plugin.authorize(pin));
    if (!r4.value("authorized").toBool()) {
        qCritical() << "FAIL: authorize failed";
        return 1;
    }

    // 5. Remove existing key (no chain code — this is the source of 0x6985)
    auto r5 = call("removeKey", plugin.removeKey());
    if (!r5.value("ok").toBool()) {
        qCritical() << "FAIL: removeKey:" << r5.value("error").toString();
        return 1;
    }

    // 6. Load BIP39 seed → stores BIP32 master key WITH chain code
    QJsonObject loadArgs;
    loadArgs["seedHex"] = TEST_SEED_HEX;
    loadArgs["keyType"] = "bip39";
    auto r6 = call("loadKey", plugin.loadKey(
        QString::fromUtf8(QJsonDocument(loadArgs).toJson(QJsonDocument::Compact))));
    if (r6.contains("error")) {
        qCritical() << "FAIL: loadKey:" << r6.value("error").toString();
        return 1;
    }
    qInfo() << "New keyUID:" << r6.value("keyUID").toString();

    // 7a. Diagnostic: export master key (no derivation) — chain code probe.
    //     If this fails with 0x6985: BIP39 load did NOT store chain code.
    //     If this succeeds: chain code is present at root; issue is in derive step.
    auto r7a = call("testMasterExport", plugin.testMasterExport(pin));
    fprintf(stderr, "  [diag] masterExport=%s pubkeyBytes=%d chainBytes=%d\n",
            r7a.value("masterExport").toString().toUtf8().constData(),
            r7a.value("pubkeyBytes").toInt(-1),
            r7a.value("chainBytes").toInt(-1));
    fflush(stderr);

    // 7b. Diagnostic: export at EXACT m/43'/60'/1581' (EIP-1581 root, 3 levels)
    //     Hypothesis: firmware only allows chain code export at the EIP-1581 root depth.
    auto r7b = call("testEip1581Export", plugin.testEip1581Export(pin));
    fprintf(stderr, "  [diag] eip1581 root export ok=%s pubkeyBytes=%d chainBytes=%d error=%s\n",
            r7b.value("ok").toBool() ? "yes" : "no",
            r7b.value("pubkeyBytes").toInt(-1),
            r7b.value("chainBytes").toInt(-1),
            r7b.value("error").toString().toUtf8().constData());
    fflush(stderr);

    // 7c. Prove: testXPUBExport — re-authorizes, derives, exports extended pubkey
    QJsonObject exportArgs;
    exportArgs["domain"] = "test-domain";
    exportArgs["pin"]    = pin;
    auto r7 = call("testXPUBExport", plugin.testXPUBExport(
        QString::fromUtf8(QJsonDocument(exportArgs).toJson(QJsonDocument::Compact))));

    if (r7.contains("error")) {
        fprintf(stderr, "FAIL: testXPUBExport: %s\n",
                r7.value("error").toString().toUtf8().constData());
        fflush(stderr);
        return 1;
    }

    fprintf(stderr, "\n*** XPUB EXPORT WORKS ***\n");
    fprintf(stderr, "  domain   : %s\n", r7.value("domain").toString().toUtf8().constData());
    fprintf(stderr, "  path     : %s\n", r7.value("path").toString().toUtf8().constData());
    fprintf(stderr, "  pubkey   : %.20s...\n", r7.value("pubkeyHex").toString().toUtf8().constData());
    fprintf(stderr, "  chainCode: %.20s...\n", r7.value("chainCodeHex").toString().toUtf8().constData());
    fflush(stderr);
    return 0;
}
