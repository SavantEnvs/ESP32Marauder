// Fuzz the WiFi CSI motion model (CsiMotionModel.cpp). On the device each CSI
// callback hands it the radio's raw CSI buffer plus RSSI and timing; here the
// input is split into records: [len][rssi][flags][dt] followed by len bytes.
#include <stddef.h>
#include <stdint.h>
#include <vector>

#include "CsiMotionModel.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  CsiMotionModel model;
  // Short calibration so fuzz inputs reach the scoring/state code.
  model.reset(0, 200);
  uint32_t now = 0;
  uint32_t accepted = 0;
  size_t pos = 0;
  while (pos + 4 <= size) {
    size_t len = data[pos];
    const int8_t rssi = static_cast<int8_t>(data[pos + 1]);
    const uint8_t flags = data[pos + 2];
    now += data[pos + 3] * 4u;
    pos += 4;
    if (len > size - pos) len = size - pos;
    std::vector<int8_t> sample(data + pos, data + pos + len);
    pos += len;
    const auto encoding = (flags & 1)
        ? CsiMotionModel::SampleEncoding::SIGNED_8_IMAG_REAL
        : CsiMotionModel::SampleEncoding::SIGNED_12_LE;
    model.addSample(sample.empty() ? nullptr : sample.data(), sample.size(), rssi,
                    now, (flags & 2) != 0, encoding);
    ++accepted;
    if (flags & 4) model.tick(now, accepted, flags >> 4);
  }
  model.tick(now + 1000, accepted, 0);
  model.calibrationPercent(now);
  return 0;
}
