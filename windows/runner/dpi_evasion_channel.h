#pragma once

#include <flutter/binary_messenger.h>

void SetupDpiEvasionChannel(flutter::BinaryMessenger* messenger);
void TeardownDpiEvasionChannel();
