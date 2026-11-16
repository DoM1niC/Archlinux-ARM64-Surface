// SPDX-License-Identifier: GPL-2.0
/*
 * Keyboard backlight of the Surface Laptop 7 as an LED class device.
 *
 * The keyboard is a HID device behind the Surface Aggregator (045E:006C). Its
 * report descriptor carries, on the Consumer page,
 *   output  report 0xd5: usage 0x7b "Keyboard Backlight Set Level" (0..12)
 *   feature report 0xd6: usage 0x7b, the current level
 *   input   report 0xd5: one bit, set while the backlight key is pressed;
 *                        the firmware itself steps through its presets
 * This driver handles the keyboard like hid-generic and adds
 * /sys/class/leds/surface::kbd_backlight on top, so desktops (via UPower) can
 * show and set the level.
 */
#include <linux/hid.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

#define SKB_REPORT_SET		0xd5
#define SKB_REPORT_GET		0xd6
#define SKB_MAX_LEVEL		12

struct skb {
	struct hid_device *hdev;
	struct led_classdev led;
	struct delayed_work key_work;
	bool have_led;
};

static int skb_led_set(struct led_classdev *led, enum led_brightness value)
{
	struct skb *skb = container_of(led, struct skb, led);
	u8 *buf;
	int ret;

	buf = kmalloc(2, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	buf[0] = SKB_REPORT_SET;
	buf[1] = value;

	ret = hid_hw_output_report(skb->hdev, buf, 2);
	if (ret == -ENOSYS)
		ret = hid_hw_raw_request(skb->hdev, SKB_REPORT_SET, buf, 2,
					 HID_OUTPUT_REPORT, HID_REQ_SET_REPORT);

	kfree(buf);
	return ret < 0 ? ret : 0;
}

static int skb_read_level(struct skb *skb)
{
	u8 *buf;
	int ret;

	buf = kzalloc(2, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	buf[0] = SKB_REPORT_GET;
	ret = hid_hw_raw_request(skb->hdev, SKB_REPORT_GET, buf, 2,
				 HID_FEATURE_REPORT, HID_REQ_GET_REPORT);
	if (ret >= 2)
		ret = min_t(int, buf[1], SKB_MAX_LEVEL);
	else if (ret >= 0)
		ret = -EIO;

	kfree(buf);
	return ret;
}

static enum led_brightness skb_led_get(struct led_classdev *led)
{
	struct skb *skb = container_of(led, struct skb, led);
	int level = skb_read_level(skb);

	return level < 0 ? led->brightness : level;
}

/* The backlight key was pressed: the firmware has picked a new level. */
static void skb_key_work(struct work_struct *work)
{
	struct skb *skb = container_of(work, struct skb, key_work.work);
	int level = skb_read_level(skb);

	if (level >= 0)
		led_classdev_notify_brightness_hw_changed(&skb->led, level);
}

static int skb_raw_event(struct hid_device *hdev, struct hid_report *report,
			 u8 *data, int size)
{
	struct skb *skb = hid_get_drvdata(hdev);

	if (skb->have_led && report->id == SKB_REPORT_SET &&
	    report->type == HID_INPUT_REPORT && size >= 2 && (data[1] & 1))
		schedule_delayed_work(&skb->key_work, msecs_to_jiffies(150));

	return 0;
}

static bool skb_has_report(struct hid_device *hdev, unsigned int type, u8 id)
{
	return hdev->report_enum[type].report_id_hash[id] != NULL;
}

static int skb_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct skb *skb;
	int ret;

	skb = devm_kzalloc(&hdev->dev, sizeof(*skb), GFP_KERNEL);
	if (!skb)
		return -ENOMEM;

	skb->hdev = hdev;
	INIT_DELAYED_WORK(&skb->key_work, skb_key_work);
	hid_set_drvdata(hdev, skb);

	ret = hid_parse(hdev);
	if (ret)
		return ret;

	ret = hid_hw_start(hdev, HID_CONNECT_DEFAULT);
	if (ret)
		return ret;

	/* Only keyboards that actually describe the backlight reports. */
	if (!skb_has_report(hdev, HID_OUTPUT_REPORT, SKB_REPORT_SET) ||
	    !skb_has_report(hdev, HID_FEATURE_REPORT, SKB_REPORT_GET))
		return 0;

	skb->led.name = "surface::kbd_backlight";
	skb->led.max_brightness = SKB_MAX_LEVEL;
	skb->led.flags = LED_BRIGHT_HW_CHANGED;
	skb->led.brightness_set_blocking = skb_led_set;
	skb->led.brightness_get = skb_led_get;

	ret = led_classdev_register(&hdev->dev, &skb->led);
	if (ret) {
		hid_warn(hdev, "keyboard backlight LED not registered: %d\n", ret);
		return 0;
	}
	skb->have_led = true;

	return 0;
}

static void skb_remove(struct hid_device *hdev)
{
	struct skb *skb = hid_get_drvdata(hdev);

	if (skb->have_led) {
		skb->have_led = false;
		led_classdev_unregister(&skb->led);
	}
	cancel_delayed_work_sync(&skb->key_work);
	hid_hw_stop(hdev);
}

static const struct hid_device_id skb_ids[] = {
	{ HID_DEVICE(BUS_HOST, HID_GROUP_ANY, 0x045e, 0x006c) },
	{ }
};
MODULE_DEVICE_TABLE(hid, skb_ids);

static struct hid_driver skb_driver = {
	.name = "surface-kbd-backlight",
	.id_table = skb_ids,
	.probe = skb_probe,
	.remove = skb_remove,
	.raw_event = skb_raw_event,
};
module_hid_driver(skb_driver);

MODULE_DESCRIPTION("Keyboard backlight of the Surface Laptop 7 (HID, via Surface Aggregator)");
MODULE_LICENSE("GPL");
