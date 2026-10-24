"""Smoke-test the exported package using ROS launch testing."""

import unittest

from launch import LaunchDescription
from launch_ros.actions import Node
import launch_testing
import launch_testing.actions
import launch_testing.asserts
from launch_testing.proc_info_handler import ProcInfoHandler
from launch_testing_ros import WaitForTopics
from std_msgs.msg import String


def generate_test_description() -> LaunchDescription:
    return LaunchDescription(
        [
            Node(
                package="demo_talker",
                executable="demo_talker",
                output="screen",
            ),
            launch_testing.actions.ReadyToTest(),
        ]
    )


class TestPublishedMessage(unittest.TestCase):

    def test_receives_expected_message(self) -> None:
        topics = WaitForTopics([("/demo_messages", String)], timeout=15.0)
        self.addCleanup(topics.shutdown)

        self.assertTrue(topics.wait(), "No message on /demo_messages within 15 seconds")

        message: String = topics.received_messages("/demo_messages")[0]
        self.assertRegex(message.data, r"^release candidate message #[0-9]+$")


@launch_testing.post_shutdown_test()
class TestProcessExit(unittest.TestCase):

    def test_exits_cleanly(self, proc_info: ProcInfoHandler) -> None:
        launch_testing.asserts.assertExitCodes(proc_info)
