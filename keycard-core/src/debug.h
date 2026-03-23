#pragma once

#include <QDebug>

// Conditional debug logging for keycard module
// Enable with: cmake -DKEYCARD_DEBUG=ON
#ifdef KEYCARD_DEBUG
#define KEYCARD_LOG(msg) qDebug() << "[KEYCARD]" << msg
#define KEYCARD_WARN(msg) qWarning() << "[KEYCARD]" << msg
#else
#define KEYCARD_LOG(msg) do {} while(0)
#define KEYCARD_WARN(msg) do {} while(0)
#endif

// Always-on production logging (errors only)
#define KEYCARD_ERROR(msg) qCritical() << "[KEYCARD ERROR]" << msg
