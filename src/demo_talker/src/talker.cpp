#include <chrono>
#include <cstddef>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

using namespace std::chrono_literals;

class DemoTalker : public rclcpp::Node
{
public:
  DemoTalker()
  : Node("demo_talker"), counter_(0)
  {
    publisher_ = create_publisher<std_msgs::msg::String>("demo_messages", 10);

    timer_ = create_wall_timer(
      1s, [this]() {
        auto message = std_msgs::msg::String();
        message.data = "release candidate message #" + std::to_string(counter_++);

        publisher_->publish(message);
        RCLCPP_INFO(get_logger(), "Published: '%s'", message.data.c_str());
      });
  }

private:
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher_;
  rclcpp::TimerBase::SharedPtr timer_;
  std::size_t counter_;
};

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<DemoTalker>());
  rclcpp::shutdown();
  return 0;
}
