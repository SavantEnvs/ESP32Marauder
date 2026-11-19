// Fuzz two over-the-air frame helpers:
//  - marauder::parseIBeacon (IBeacon.h): scans BLE manufacturer data from an
//    advertisement for an Apple iBeacon record
//  - setBeaconFrameChannel (BeaconFrame.cpp): patches the DS-parameter channel
//    in a beacon frame given a frame buffer and SSID length
// Byte 0 = SSID length, byte 1 = channel, rest = the frame / mfr-data bytes in
// an exact-size heap buffer.
#include <stddef.h>
#include <stdint.h>
#include <vector>

#include "BeaconFrame.h"
#include "IBeacon.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 2) return -1;
  const size_t ssid_length = data[0];
  const uint8_t channel = data[1];
  std::vector<uint8_t> frame(data + 2, data + size);

  marauder::IBeaconPayload beacon;
  marauder::parseIBeacon(frame.empty() ? nullptr : frame.data(), frame.size(), beacon);

  if (!frame.empty())
    setBeaconFrameChannel(frame.data(), frame.size(), ssid_length, channel);
  return 0;
}
