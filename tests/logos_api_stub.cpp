// Minimal LogosAPI + LogosAPIClient stubs for tests — no liblogos_sdk.a linked.
// BeaconPlugin tests never call initLogos() so only type definitions are needed.

#include "logos_api.h"
#include "cpp/logos_api_client.h"

LogosAPI::LogosAPI(const QString& /*module_name*/, QObject* parent)
    : QObject(parent), m_provider(nullptr), m_token_manager(nullptr) {}

LogosAPI::~LogosAPI() {}

LogosAPIProvider* LogosAPI::getProvider() const { return nullptr; }
LogosAPIClient*   LogosAPI::getClient(const QString&) const { return nullptr; }
TokenManager*     LogosAPI::getTokenManager() const { return nullptr; }

bool LogosAPIClient::isConnected() const { return false; }

QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariantList&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, const QVariant&, const QVariant&, Timeout) { return {}; }

void LogosAPIClient::onEvent(
    LogosObject*, const QString&,
    std::function<void(const QString&, const QVariantList&)>) {}
