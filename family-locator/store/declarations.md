# Permission declarations and review notes

## Google Play → App content → Sensitive permissions → Location permissions

**Background location: why does the app need it?**

```
Family Locator is a parental safety app. A child's phone shares its location with the parents
in their family so parents get an alert when the child arrives at or leaves a saved place (home,
school), see where the child is, and receive the child's exact position when the child presses
SOS. These alerts must work while the app is closed, which requires background location. A
persistent notification is shown on the child's phone whenever sharing is on, the child can see
exactly what is shared and when a parent looked, and sharing can be paused. Location is only
visible to members of the family and history is deleted after 30 days.
```

**Feature that uses it:** Place arrival/departure alerts, live family map, SOS location.

**Video** (required, 30 seconds or less, unlisted YouTube link). Record on a real Android phone:
1. Child phone: open the app, enter the family code.
2. The in-app disclosure ("Share your location with your family…") appears. Tap Continue.
3. The system prompt appears. Choose "While using", then "Allow all the time" in settings.
4. Show the "Sharing location with your family" notification in the shade.
5. Parent phone: the child appears on the map. Walk out of the "Home" place and show the
   "left Home" alert arriving.

<!-- FILL: record and upload the video, then paste the link in Play Console. -->

## Google Play → Foreground service types

- Type: **location**
- Description: `Shares the child's location with their family while the app is in the background, for arrival alerts and SOS. A notification is always visible.`
- Video: same as above.

## Google Play → Stalkerware / monitoring

The manifest declares `<meta-data android:name="isMonitoringTool" android:value="child_monitoring"/>`.
The app is never hidden, always shows a notification while sharing, and the listing states that it
monitors children. Don't remove any of these.

## Google Play → Account deletion

- In-app path: Settings → Delete my account / ⋮ → Delete my data and leave
- Web URL: the hosted `store/delete-account.md`

## Apple: App Review notes

```
Family Locator lets parents see the location of their children's phones within a private family
group, with SOS and arrival alerts. No login is needed. Accounts are created anonymously.

To review with one device:
1. Launch, tap "I'm a parent: set up my family", enter any name.
2. Settings → Add family member shows a 6-letter code.
3. Delete and reinstall the app (or use a second device), tap "I have a family code", choose
   "I'm the child", and enter the code. The location disclosure and permission prompts follow.
Background location ("Always") is used so arrival alerts and SOS work when the app is closed;
the blue location indicator is shown while active. Push notifications deliver alerts and the
"ring loudly" signal. Account deletion: Settings → Delete my account.
```

**Background modes justification** (if asked): *location*: arrival alerts and SOS for the child's
device. *remote-notification*: deliver the parent's "ring" signal and alerts.

**Optional: Critical Alerts entitlement.** To let SOS sound through Do Not Disturb, request it at
https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/ . Without it
the app still works and SOS uses a time-sensitive notification.
