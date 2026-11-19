// Fuzz the ASTM F3411 Remote ID decoder (RemoteIdDecoder.cpp) the way the
// firmware's sniffer feeds it: whole 802.11 management frames (beacon / NAN
// action frames, WiFiScanRemoteId.h) and BLE Service Data AD values, then the
// decoded record goes into a RemoteIdStore like the live scanner does.
// Byte 0 selects the entry point; the rest is the over-the-air payload, copied
// into an exact-size heap buffer so any overread is caught by ASan.
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <vector>

#include "RemoteIdDecoder.h"
#include "RemoteIdModel.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  const uint8_t selector = data[0];
  std::vector<uint8_t> payload(data + 1, data + size);
  const uint8_t* p = payload.empty() ? nullptr : payload.data();
  const size_t n = payload.size();

  RemoteIdDecoder decoder;
  RemoteIdRecord decoded;
  RemoteIdDecodeResult result = RemoteIdDecodeResult::Ignored;
  RemoteIdTransport transport = RemoteIdTransport::WifiBeacon;
  switch (selector % 5) {
    case 0:
      // WiFiScanRemoteId.h: beacon first, NAN as fallback on the same frame.
      result = decoder.decodeWifiBeacon(p, n, decoded);
      if (result != RemoteIdDecodeResult::Decoded)
        result = decoder.decodeWifiNan(p, n, decoded);
      break;
    case 1:
      transport = RemoteIdTransport::WifiNan;
      result = decoder.decodeWifiNan(p, n, decoded);
      break;
    case 2:
      transport = RemoteIdTransport::BleLegacy;
      result = decoder.decodeBleServiceData(p, n, decoded);
      break;
    case 3:
      result = decoder.decodePayload(p, n, decoded);
      break;
    default:
      result = decoder.decodeMessage(p, n, decoded);
      break;
  }
  if (result != RemoteIdDecodeResult::Decoded) return 0;

  RemoteIdRecord records[4];
  RemoteIdStore store(records, 4);
  RemoteIdRecord& record = store.observe(decoded.mac, transport, -50, 1000);
  if (decoded.hasLocation)
    remoteIdUpdateLocation(record, decoded.latitudeE7, decoded.longitudeE7);
  store.findByUasId(decoded.uasId);
  remoteIdIdentityMatches(decoded.uasId, decoded.mac, record);
  char text[32];
  remoteIdFormatTransports(record.transportMask, text, sizeof(text));
  store.updateLifecycle(5000, 2000);
  store.pruneStale(100000, 1000, decoded.uasId, decoded.mac);
  return 0;
}
