#include "baldr/sign.h"
#include "baldr/signinfo.h"
#include "odin/sign.h"
#include "test.h"

#include <algorithm>
#include <cstdint>
#include <vector>

using namespace std;
using namespace valhalla::odin;
using namespace valhalla::baldr;

// Expected size is 8 bytes. We want to alert if somehow any change grows
// this structure size as that indicates incompatible tiles.
constexpr size_t kSignExpectedSize = 8;

namespace {

TEST(Sign, test_sizeof) {
  EXPECT_EQ(sizeof(valhalla::baldr::Sign), kSignExpectedSize);
}

void TryCtor(const std::string& text, const bool is_route_number) {
  valhalla::odin::Sign sign(text, is_route_number);
  uint32_t consecutive_count = 0;

  EXPECT_EQ(text, sign.text());
  EXPECT_EQ(is_route_number, sign.is_route_number());
  EXPECT_EQ(consecutive_count, sign.consecutive_count());
}

TEST(Sign, TestCtor) {
  // Exit number
  TryCtor("51A", false);

  // Exit branch
  TryCtor("I 81 South", true);

  // Exit toward
  TryCtor("Carlisle", false);

  // Exit name
  TryCtor("Harrisburg East", false);
}

void TryDescendingSortByConsecutiveCount(std::vector<valhalla::odin::Sign>& signs,
                                         const std::vector<valhalla::odin::Sign>& expectedSigns) {

  EXPECT_EQ(signs.size(), expectedSigns.size()) << "DescendingSortByConsecutiveCount size mismatch";

  std::sort(signs.begin(), signs.end(),
            [](const valhalla::odin::Sign& lhs, const valhalla::odin::Sign& rhs) {
              return lhs.consecutive_count() > rhs.consecutive_count();
            });

  for (size_t x = 0, n = signs.size(); x < n; ++x) {
    EXPECT_EQ(signs.at(x).consecutive_count(), expectedSigns.at(x).consecutive_count())
        << "Incorrect DescendingSortByConsecutiveCount";
  }
}

TEST(Sign, TestDescendingSortByConsecutiveCount_0_1) {
  valhalla::odin::Sign signConsecutiveCount0("Elizabethtown", false);

  valhalla::odin::Sign signConsecutiveCount1("Hershey", false);
  signConsecutiveCount1.set_consecutive_count(1);

  std::vector<valhalla::odin::Sign> signs = {signConsecutiveCount0, signConsecutiveCount1};

  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount1, signConsecutiveCount0});
}

TEST(Sign, TestDescendingSortByConsecutiveCount_1_2) {
  valhalla::odin::Sign signConsecutiveCount1("I 81 South", true);
  signConsecutiveCount1.set_consecutive_count(1);

  valhalla::odin::Sign signConsecutiveCount2("I 81 North", true);
  signConsecutiveCount2.set_consecutive_count(2);

  std::vector<valhalla::odin::Sign> signs = {signConsecutiveCount1, signConsecutiveCount2};

  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount2, signConsecutiveCount1});
}

TEST(Sign, TestDescendingSortByConsecutiveCount_2_4) {
  valhalla::odin::Sign signConsecutiveCount2("51A", false);
  signConsecutiveCount2.set_consecutive_count(2);

  valhalla::odin::Sign signConsecutiveCount4("51B", false);
  signConsecutiveCount4.set_consecutive_count(4);

  std::vector<valhalla::odin::Sign> signs = {signConsecutiveCount2, signConsecutiveCount4};

  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount4, signConsecutiveCount2});
}

TEST(Sign, TestDescendingSortByConsecutiveCount_0_1_2) {
  valhalla::odin::Sign signConsecutiveCount0("Towson", false);

  valhalla::odin::Sign signConsecutiveCount1("Baltimore", false);
  signConsecutiveCount1.set_consecutive_count(1);

  valhalla::odin::Sign signConsecutiveCount2("New York", false);
  signConsecutiveCount2.set_consecutive_count(2);

  std::vector<valhalla::odin::Sign> signs = {signConsecutiveCount0, signConsecutiveCount1,
                                             signConsecutiveCount2};

  // Reverse order
  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount2, signConsecutiveCount1,
                                              signConsecutiveCount0});

  signs = {signConsecutiveCount2, signConsecutiveCount1, signConsecutiveCount0};

  // In order
  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount2, signConsecutiveCount1,
                                              signConsecutiveCount0});

  signs = {signConsecutiveCount0, signConsecutiveCount2, signConsecutiveCount1};

  // Mixed order
  TryDescendingSortByConsecutiveCount(signs, {signConsecutiveCount2, signConsecutiveCount1,
                                              signConsecutiveCount0});
}

} // namespace

int main(int argc, char* argv[]) {
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
