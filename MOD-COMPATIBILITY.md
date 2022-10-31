The mod raises a number of custom events based around if it will/won't revive biters and if the revives are successful or not. This allows other mods to react to non revived biters (truly dead) and avoid reacting to biters that are revived as if they actually died.




Biter Won't Be Revived
======================

When a biter dies and it isn't planned to be revived (due to any reason) then this event is raised. This allows other mods to only react to biters that aren't planned to be revived, with a separate event for biters that the mod tries to revive, but fails for.

#### Get custom event Id

You will need to get the custom event Id for your mod to listen to via a remote interface call. This returns the event Id to subscribe too.

```
remote.call("biter_revive", "get_biter_wont_be_revived_event_id")
```

#### Custom event

The custom event will include the below event specific fields in addition to the core Factorio ones.

| Name | Type | Details |
| --- | --- | --- |
| entity | LuaEntity | Reference to the entity that died. |
| unitNumber | uint | The entity's `unit_number` value. All unit types have one. |
| entityName | string? | The entity's `name` value if it was already obtained by the Biter revive code, otherwise nil. |
| force | LuaForce? | The entity's `force` value if it was already obtained by the Biter revive code, otherwise nil. |
| forceIndex | uint? | The entity's `force`'s `index` value if the `force` field was already obtained by the Biter revive code, otherwise nil. |




Biter Will Be Revived
======================

When a biter dies and it is planned to be revived then this event is raised. A separate event will be raised at the time of the biters revival for if it was successful or not. With the `unitNumber` field being used to match them up.

#### Get custom event Id

You will need to get the custom event Id for your mod to listen to via a remote interface call. This returns the event Id to subscribe too.

```
remote.call("biter_revive", "get_biter_will_be_revived_event_id")
```

#### Custom event

The custom event will include the below event specific fields in addition to the core Factorio ones.

| Name | Type | Details |
| --- | --- | --- |
| entity | LuaEntity | Reference to the entity that died. |
| unitNumber | uint | The entity's `unit_number` value. All unit types have one. |
| entityName | string | The entity's `name` value. |
| force | LuaForce | The entity's `force` value. |
| forceIndex | uint | The entity's `force`'s `index` value. |
| surface | LuaSurface | The entity's `surface` value. |
| orientation | RealOrientation | The entity's `orientation` value. |




Biter Revive Success
======================

When a biter revive is successfully completed this event fires. It follows on from the Biter Will Be Revived event. With the `unitNumber` field being used to match them up.

#### Get custom event Id

You will need to get the custom event Id for your mod to listen to via a remote interface call. This returns the event Id to subscribe too.

```
remote.call("biter_revive", "get_biter_revive_success_event_id")
```

#### Custom event

The custom event will include the below event specific fields in addition to the core Factorio ones.

| Name | Type | Details |
| --- | --- | --- |
| unitNumber | uint | The `unit_number` value of the entity that died previously. All unit types have one. |
| prototypeName | string | The `name` value of the entity that died previously. |
| force | LuaForce | The `force` value of the entity that died previously. |
| forceIndex | uint | The entity's `force`'s `index` value. |
| surface | LuaSurface | The `surface` value of the entity that died previously. |
| position | LuaSurface | The `position` value of the entity that died previously. |
| orientation | RealOrientation | The `orientation` value of the entity that died previously. |




Biter Revive Failure
======================

When a biter revive fails this event fires. It follows on from the Biter Will Be Revived event. With the `unitNumber` field being used to match them up.

#### Get custom event Id

You will need to get the custom event Id for your mod to listen to via a remote interface call. This returns the event Id to subscribe too.

```
remote.call("biter_revive", "get_biter_revive_failed_event_id")
```

#### Custom event

The custom event will include the below event specific fields in addition to the core Factorio ones.

| Name | Type | Details |
| --- | --- | --- |
| unitNumber | uint | The `unit_number` value of the entity that died previously. All unit types have one. |
| prototypeName | string | The `name` value of the entity that died previously. |
| force | LuaForce | The `force` value of the entity that died previously. |
| forceIndex | uint | The entity's `force`'s `index` value. |
| surface | LuaSurface | The `surface` value of the entity that died previously. |
| position | LuaSurface | The `position` value of the entity that died previously. |
| orientation | RealOrientation | The `orientation` value of the entity that died previously. |




General Notes
=========

- To ensure correct ordering of these events its advised to have this Biter Revive mod as dependency of some type on your mod. So that Biter revive loads and has its events run first.
- These events allow other mods to not need to listen to when a unit dies via Factorio events. The event `on_entity_died` with the filter of `{ filter = "type", type = "unit" }` can be ignored unless you want the extra information on the event.
- The custom events often include pre-obtained fields from the died entity. This is as they were obtained via API calls as part of this mods processing and so are included to help reduce other mods need to duplicate these Factorio API calls.
- Some of the custom events have optional fields that they may include, type of `?`. This is based on the logic within the mod that may have already obtained these values. No fields are obtained specifically for inclusion in events.
- This mod only raises a custom event if another mod has requested the relevant custom event Id via the remote interface. This is to avoid the mod raising the custom events in to Factorio if no other mod is going to utilise them.