# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_target — game tests

  @kora_target @legacy:tgt-start @target:1
  Scenario: Resource starts cleanly
    """
    1. Join the server and load into your character.
    2. Press F8 and scroll through the console.
    3. Hold Left Alt for a second, then let go.
    Expect: no red errors or 'script error' lines that mention kora_target, and no '[kora_target] ... errored' lines. While Left Alt is held a small dot shows in the middle of the screen.
    """
    When I press the "F8" key
    And I manually: scroll through the console
    And the F8 console should show no errors
    Then there should be no script errors
    And I confirm: the F8 console has no '[kora_target] ... errored' lines
    When I manually: hold Left Alt for a second, then let go
    Then I confirm: a small dot shows in the middle of my screen while Left Alt is held

  @kora_target @legacy:tgt-eye-open @target:2 @checklist @checklist:kora_target:hold-to-target @cat:core-and-libraries @manual
  Scenario: Open and close the target eye
    """
    1. Stand somewhere open with nothing in front of you.
    2. Hold Left Alt. Look around with the mouse, then walk, sprint and jump while still holding it.
    3. Let go of Left Alt.
    Expect: a small dot appears in the centre of the screen while Alt is held and disappears when you let go. The camera and movement keep working normally the whole time, no mouse cursor appears, and letting go with nothing aimed at does nothing.
    Also checklist kora_target:hold-to-target (Hold Left Alt to target): Hold LAlt: crosshair/eye appears and highlights interactable entities/zones; release without selecting runs nothing.
    """
    When I manually: stand somewhere open with nothing in front of me
    And I manually: hold Left Alt, look around with the mouse, then walk, sprint and jump while still holding it
    Then I confirm: a small dot appears in the centre of my screen while Alt is held
    And I confirm: my camera and movement keep working normally and no mouse cursor appears
    When I manually: let go of Left Alt
    Then I confirm: the dot disappears and letting go with nothing aimed at does nothing

  @kora_target @legacy:tgt-prop-prompt @target:2
  Scenario: Prompt and select on a test prop
    """
    1. Type /testtarget_entity in chat. A beach umbrella spawns 2 m in front of you.
    2. Hold Left Alt and aim the dot at the umbrella.
    3. Let go of Left Alt, then press F8.
    4. Type /testtarget_entity_remove when done.
    Expect: over the umbrella the dot brightens and a box under it reads 'Inspect' with 'Release Alt to interact'. 'Always hidden' never shows. After letting go, F8 shows 'target: Inspect selected'. The remove command deletes the umbrella.
    """
    When I run the command "/testtarget_entity"
    Then I confirm: a beach umbrella spawns 2 m in front of me
    When I manually: hold Left Alt and aim the dot at the umbrella
    Then I confirm: the dot brightens and a box under it reads 'Inspect' with 'Release Alt to interact'
    And I confirm: 'Always hidden' never shows
    When I manually: let go of Left Alt
    And I press the "F8" key
    And the F8 console should show "target: Inspect selected"
    And I run the command "/testtarget_entity_remove"
    Then I confirm: the umbrella is deleted

  @kora_target @legacy:tgt-aim-away @target:2
  Scenario: Prompt follows where you aim
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Hold Left Alt and sweep the dot on and off the umbrella a few times, slowly and quickly.
    3. Move the dot off it onto empty ground, then let go of Left Alt.
    Expect: the 'Inspect' box appears as soon as the dot is on the umbrella and goes away as soon as it leaves, with no noticeable lag or flicker. Letting go while aiming at the ground runs nothing (no 'Inspect selected' line in F8).
    """
    When I run the command "/testtarget_entity"
    And I manually: hold Left Alt and sweep the dot on and off the umbrella a few times, slowly and quickly
    Then I confirm: the 'Inspect' box appears as soon as the dot is on the umbrella and goes away as soon as it leaves, with no noticeable lag or flicker
    When I manually: move the dot onto empty ground, then let go of Left Alt
    Then I confirm: nothing runs and F8 has no 'Inspect selected' line

  @kora_target @legacy:tgt-zone @target:2
  Scenario: Target a box zone on the ground
    """
    1. Type /testtarget_zone. A box outline is drawn around where you stand.
    2. Step back about 1.5 m out of the box.
    3. Hold Left Alt and aim at the ground inside the outline, then let go.
    4. Aim at ground just outside the outline.
    5. Type /testtarget_zone_remove and aim at the spot again.
    Expect: inside the outline the prompt reads 'Test zone action' and letting go prints 'zone action selected' in F8. Outside the outline, or after removing it, nothing shows. You don't need to stand inside the box.
    """
    When I run the command "/testtarget_zone"
    Then I confirm: a box outline is drawn around where I stand
    When I manually: step back about 1.5 m out of the box
    And I manually: hold Left Alt, aim at the ground inside the outline, then let go
    Then I confirm: the prompt reads 'Test zone action'
    When the F8 console should show "zone action selected"
    And I manually: hold Left Alt and aim at ground just outside the outline
    Then I confirm: nothing shows
    When I run the command "/testtarget_zone_remove"
    And I manually: hold Left Alt and aim at the same spot again
    Then I confirm: nothing shows after removing the zone

  @kora_target @legacy:tgt-distance @target:2
  Scenario: Options only show when close enough
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Walk about 6 m away, hold Left Alt and aim at it.
    3. Keep holding and walk slowly towards it.
    4. Repeat at a vending machine (shows from about 2.5 m) and a car's hood (about 3 m).
    Expect: far away, only the dot shows and there's no prompt. The prompt appears once you are roughly 2.5 m from the spot you aim at, and goes away again when you back off.
    """
    When I run the command "/testtarget_entity"
    And I manually: walk about 6 m away, hold Left Alt and aim at the umbrella
    Then I confirm: only the dot shows and there is no prompt
    When I manually: keep holding Alt and walk slowly towards the umbrella
    Then I confirm: the prompt appears once I am roughly 2.5 m from the spot I aim at and goes away when I back off
    When I manually: repeat at a vending machine and at a car's hood
    Then I confirm: the prompt shows from about 2.5 m at the vending machine and about 3 m at the car hood

  @kora_target @legacy:tgt-multi-menu @target:2
  Scenario: Choose from several options at a car trunk
    """
    Needs a car you can get into (unlocked).
    1. Stand behind the car, hold Left Alt and aim at the trunk.
    2. Let go of Left Alt.
    3. Use the scroll wheel or Up/Down arrows to move, then press E (or left-click) on 'Open trunk'.
    Expect: while aiming, the prompt reads '2 options' with 'Release Alt to choose'. Letting go opens a small list with 'Open trunk' and 'Trunk storage'. The highlight moves with scroll/arrows, and choosing 'Open trunk' opens it. Next time the list shows 'Close trunk'.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: stand behind the car, hold Left Alt and aim at the trunk
    Then I confirm: the prompt reads '2 options' with 'Release Alt to choose'
    When I manually: let go of Left Alt
    Then I confirm: a small list opens with 'Open trunk' and 'Trunk storage'
    When I manually: use the scroll wheel or Up/Down arrows to move, then press E on 'Open trunk'
    Then I confirm: the highlight moves with scroll/arrows and the trunk opens
    When I manually: open the list again by aiming at the trunk with Left Alt and letting go
    Then I confirm: the list now shows 'Close trunk'

  @kora_target @legacy:tgt-single-instant @target:2
  Scenario: A single option runs straight away
    """
    Needs a car you can get into.
    1. Stand at the front of the car, hold Left Alt and aim at the hood.
    2. Let go of Left Alt.
    3. Aim at the hood again and let go.
    Expect: the prompt reads 'Open hood'. Letting go opens the hood right away with no list in between. The second time the prompt reads 'Close hood' and closes it.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: stand at the front of the car, hold Left Alt and aim at the hood
    Then I confirm: the prompt reads 'Open hood'
    When I manually: let go of Left Alt
    Then I confirm: the hood opens right away with no list in between
    When I manually: aim at the hood again with Left Alt and let go
    Then I confirm: the prompt read 'Close hood' and the hood closes

  @kora_target @legacy:tgt-menu-escape @target:2
  Scenario: Close the option list with Escape
    """
    1. Open the trunk option list (aim at a car trunk with Left Alt, let go).
    2. Press Escape.
    3. Open it again and press Backspace. Open it again and right-click.
    Expect: each key closes the list without picking anything (trunk does not open). Escape does NOT also open the GTA pause menu. Pressing Escape again afterwards opens the pause menu normally.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: open the trunk option list (aim at the trunk with Left Alt, let go)
    And I press the "ESCAPE" key
    Then I confirm: the list closes, the trunk does not open and the GTA pause menu does not open
    When I manually: open the list again and press Backspace
    Then I confirm: the list closes without opening the trunk
    When I manually: open the list again and right-click
    Then I confirm: the list closes without opening the trunk
    When I manually: press Escape again
    Then I confirm: the pause menu opens normally

  @kora_target @legacy:tgt-menu-walk-away @target:2
  Scenario: Option list closes when you walk away
    """
    1. Open the trunk option list on a car.
    2. Walk around a little while staying close to the trunk.
    3. Now walk away from the car, about 5 m.
    Expect: you can move freely while the list is open and it stays open while you are near the trunk. Once you are out of reach it closes by itself. Picking an option after the list closes is impossible.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: open the trunk option list on the car
    And I manually: walk around a little while staying close to the trunk
    Then I confirm: I can move freely and the list stays open while I am near the trunk
    When I manually: walk about 5 m away from the car
    Then I confirm: the list closes by itself once I am out of reach
    And I confirm: picking an option after the list closes is impossible

  @kora_target @legacy:tgt-menu-idle @target:1
  Scenario: Option list closes after 30 seconds idle
    """
    1. Open the trunk option list on a car.
    2. Stand still and don't scroll or press anything for 30 seconds.
    3. Repeat, but scroll the list every 10 seconds or so.
    Expect: untouched, the list closes on its own after about 30 seconds and nothing is chosen. Scrolling resets the timer so it stays open while you use it.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: open the trunk option list on the car
    And I wait 32 seconds
    Then I confirm: the list closed on its own after about 30 seconds and nothing was chosen
    When I manually: open the list again and scroll it every 10 seconds or so for over 30 seconds
    Then I confirm: scrolling resets the timer and the list stays open while I use it

  @kora_target @legacy:tgt-cancel-hold @target:2
  Scenario: Cancel targeting while still holding Alt
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Hold Left Alt, aim at it so 'Inspect' shows, then right-click while still holding Alt.
    3. Let go of Left Alt and check F8.
    4. Repeat pressing Backspace, then Escape, instead of right-click.
    Expect: the dot and prompt disappear at once and letting go runs nothing (no 'Inspect selected' in F8). Escape does not leave you in the pause menu. Holding Alt again works normally.
    """
    When I run the command "/testtarget_entity"
    And I manually: hold Left Alt, aim at the umbrella so 'Inspect' shows, then right-click while still holding Alt
    Then I confirm: the dot and prompt disappear at once
    When I manually: let go of Left Alt
    And I press the "F8" key
    Then I confirm: nothing ran and F8 has no 'Inspect selected' line
    When I manually: repeat pressing Backspace, then Escape, instead of right-click
    Then I confirm: the dot and prompt disappear and nothing runs each time
    And I confirm: Escape does not leave me in the pause menu
    When I manually: hold Left Alt again
    Then I confirm: targeting works normally

  @kora_target @legacy:tgt-in-vehicle @target:2 @checklist @checklist:kora_target:no-target-in-vehicle @cat:core-and-libraries
  Scenario: No targeting while seated in a vehicle
    """
    1. Get into a car as the driver.
    2. Hold Left Alt and aim at another car's hood, a fuel pump or a shop clerk.
    3. Move to a passenger seat (or have a friend drive) and try again.
    4. Get out and try again.
    Expect: while seated (driver or passenger), holding Alt shows no dot and no prompt at all. Once you are out of the car, targeting works again.
    Also checklist kora_target:no-target-in-vehicle (Targeting disabled while seated): Inside a vehicle holding LAlt does not open targeting; entering a vehicle closes an open eye.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: hold Left Alt and aim at another car's hood, a fuel pump or a shop clerk
    Then I confirm: no dot and no prompt show
    When I manually: move to a passenger seat (or have a friend drive) and hold Left Alt again
    Then I confirm: no dot and no prompt show
    When I get out of the vehicle
    And I manually: hold Left Alt and aim at something targetable
    Then I confirm: targeting works again

  @kora_target @legacy:tgt-enter-vehicle-close @target:2
  Scenario: Getting into a car closes the eye and list
    """
    Needs a car you can get into.
    1. Open the trunk option list, walk to the door and press F to get in.
    2. Get out. Hold Left Alt near the car and, still holding it, press F to get in.
    Expect: the option list closes as soon as you are seated. The dot and prompt also disappear once you are seated, and letting go of Alt in the car does nothing.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: open the trunk option list on the car
    And I get in the vehicle
    Then I should be in a vehicle
    And I confirm: the option list closes as soon as I am seated
    And I confirm: the dot and prompt are gone once seated
    When I manually: hold Left Alt and let go in the car
    Then I confirm: letting go does nothing
    When I get out of the vehicle
    And I manually: hold Left Alt near the car and, still holding it, press F to get in
    Then I confirm: the dot and prompt disappear once I am seated and letting go does nothing

  @kora_target @legacy:tgt-progressbar @target:2
  Scenario: No targeting during a progress bar
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Type /testprogressbar. An 8 second bar 'Testing progress bar...' starts.
    3. While it runs, hold Left Alt and aim at the umbrella.
    4. Wait for the bar to finish and try again.
    Expect: during the bar, holding Alt shows no dot and no prompt. After it ends, the 'Inspect' prompt works again.
    """
    When I run the command "/testtarget_entity"
    And I run the command "/testprogressbar"
    Then a progress bar labelled "Testing progress bar..." should run
    When I manually: hold Left Alt and aim at the umbrella while the bar runs
    Then I confirm: no dot and no prompt show during the bar
    When I wait 8 seconds
    And I manually: hold Left Alt and aim at the umbrella again
    Then I confirm: the 'Inspect' prompt works again

  @kora_target @legacy:tgt-dead @target:1 @checklist @checklist:kora_target:no-target-while-dead @cat:core-and-libraries
  Scenario: No targeting while dead
    """
    Needs a way to die, e.g. jump off a tall building.
    1. Stand near a vending machine or a car and die.
    2. Before you respawn, hold Left Alt and aim at the machine or car.
    3. After you are back up, try again.
    Expect: while dead, holding Alt shows no dot and no prompt, and nothing can be selected. Once you are alive again, targeting works normally.
    Also checklist kora_target:no-target-while-dead (Targeting blocked while downed): Downed/last-stand players cannot open the eye or run options.
    """
    Given a "test_car" is spawned in front of me
    And I am dead
    Then I should be dead
    When I manually: hold Left Alt and aim at the car before respawning
    Then I confirm: no dot and no prompt show and nothing can be selected
    When I manually: get back up (respawn or get revived)
    Then I should be alive
    When I manually: hold Left Alt and aim at the car
    Then I confirm: targeting works normally

  @kora_target @legacy:tgt-charselect @target:1 @manual
  Scenario: No targeting on character select or spawn picker
    """
    1. Join the server (or go back to character select).
    2. On the character select screen, and again on the spawn location screen, hold Left Alt and look around.
    Expect: no dot, no prompt and no menus appear while choosing a character or spawn. After you spawn in, Left Alt works as normal.
    """
    When I manually: join the server or go back to character select
    And I manually: on the character select screen and the spawn location screen, hold Left Alt and look around
    Then I confirm: no dot, no prompt and no menus appear while choosing a character or spawn
    When I manually: spawn in and hold Left Alt
    Then I confirm: Left Alt works as normal

  @kora_target @legacy:tgt-alttab @target:2
  Scenario: Alt+Tab does not leave targeting stuck
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Hold Left Alt, aim at it, then press Tab to Alt+Tab out of the game.
    3. Come back to the game. Check F8.
    4. Open a car's trunk option list and Alt+Tab out and back.
    Expect: when you come back the dot and prompt are gone, nothing was selected (no 'Inspect selected'), and the option list has closed. The next Left Alt hold works normally.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I run the command "/testtarget_entity"
    And I manually: hold Left Alt, aim at the umbrella, then press Tab to Alt+Tab out of the game
    And I manually: come back to the game
    And I press the "F8" key
    Then I confirm: the dot and prompt are gone and F8 has no 'Inspect selected' line
    When I manually: open the car's trunk option list, then Alt+Tab out and back
    Then I confirm: the option list has closed
    When I manually: hold Left Alt again
    Then I confirm: the next Left Alt hold works normally

  @kora_target @legacy:tgt-reset-cmd @target:1
  Scenario: Force-clear targeting with /target-reset
    """
    1. Open a car's trunk option list.
    2. Press F8, type target-reset and press Enter. Close F8.
    3. Type /target-reset in chat with nothing open.
    4. Hold Left Alt and aim at something.
    Expect: the open list closes straight away. The chat command gives no error with nothing open. Targeting works normally afterwards.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle is unlocked
    When I manually: open the car's trunk option list
    And I press the "F8" key
    And I manually: type target-reset and press Enter, then close F8
    Then I confirm: the open list closes straight away
    When I run the command "/target-reset"
    Then I confirm: the chat command gives no error with nothing open
    When I manually: hold Left Alt and aim at something
    Then I confirm: targeting works normally

  @kora_target @legacy:tgt-rebind @target:2
  Scenario: Rebind the target key
    """
    1. Escape > Settings > Key Bindings > FiveM. Find 'Hold to target' and set it to G.
    2. Spawn the umbrella with /testtarget_entity. Hold Left Alt and aim at it, then hold G instead.
    3. Rebind it back to Left Alt and check it works.
    Expect: after rebinding, Left Alt no longer opens the eye and G does (prompt and selection work). Note in your result whether the prompt still says 'Release Alt' while using G. Setting it back to Left Alt restores normal use.
    """
    When I manually: open Escape > Settings > Key Bindings > FiveM and set 'Hold to target' to G
    And I run the command "/testtarget_entity"
    And I manually: hold Left Alt and aim at the umbrella, then release
    Then I confirm: Left Alt no longer opens the eye
    When I manually: hold G and aim at the umbrella, then release
    Then I confirm: G opens the eye and the prompt and selection work
    And I confirm: I note in my result whether the prompt still says 'Release Alt' while using G
    When I manually: rebind 'Hold to target' back to Left Alt
    And I manually: hold Left Alt and aim at the umbrella
    Then I confirm: Left Alt works normally again

  @kora_target @legacy:tgt-ui-look @target:2
  Scenario: Target prompt looks right
    """
    1. Aim at the test umbrella (/testtarget_entity), then a car trunk, with Left Alt held.
    2. Try it in daylight, at night and against bright and dark backgrounds.
    3. Try a few screen resolutions or window sizes if you can.
    Expect: the dot sits in the exact screen centre and gets brighter over a target. The box sits just below the dot, with the option name in bold and a smaller grey hint ('Release Alt to interact' or 'Release Alt to choose'). Text is readable, never cut off oddly, and colours match the rest of the server UI.
    """
    When I run the command "/testtarget_entity"
    And I manually: hold Left Alt and aim at the test umbrella
    And I manually: hold Left Alt and aim at a car trunk
    And I manually: repeat in daylight, at night and against bright and dark backgrounds
    And I manually: try a few screen resolutions or window sizes if possible
    Then I confirm: the dot sits in the exact screen centre and gets brighter over a target
    And I confirm: the box sits just below the dot with the option name in bold and a smaller grey hint ('Release Alt to interact' or 'Release Alt to choose')
    And I confirm: the text is readable, never cut off oddly, and colours match the rest of the server UI

  @kora_target @legacy:tgt-fuel-pump @target:2
  Scenario: Target a fuel pump
    """
    1. Go to any gas station and stand next to a pump, with a car parked beside it.
    2. Hold Left Alt and aim at the pump, then let go.
    3. Back off about 4 m from the pump and try again.
    Expect: up close the prompt reads 'Service nearby vehicle' and letting go opens the fuel menu for the car. From 4 m away no prompt shows.
    """
    When I manually: go to any gas station and stand next to a pump with a car parked beside it
    And I manually: hold Left Alt, aim at the pump, then let go
    Then the text UI should show "Service nearby vehicle"
    And I confirm: letting go opens the fuel menu for the car
    When I manually: back off about 4 m from the pump, hold Left Alt and aim at it
    Then I confirm: no prompt shows from 4 m away

  @kora_target @legacy:tgt-vending @target:2
  Scenario: Target a vending machine
    """
    1. Find a vending machine (drinks or snacks machine) anywhere in the city.
    2. Stand next to it, hold Left Alt and aim at it, then let go.
    Expect: the prompt reads 'Browse Vending Machine' and letting go opens the vending machine shop. It works on every vending machine of that type you find.
    """
    When I manually: find a vending machine (drinks or snacks) and stand next to it
    And I manually: hold Left Alt, aim at the machine, then let go
    Then the text UI should show "Browse Vending Machine"
    And I confirm: letting go opens the vending machine shop
    And I confirm: this works on every vending machine of that type I find

  @kora_target @legacy:tgt-shop-clerk @target:2 @manual
  Scenario: Target a 24/7 shop clerk
    """
    1. Walk into any 24/7 store.
    2. Hold Left Alt and aim at the clerk behind the counter, then let go.
    3. Aim at the counter and the till too.
    Expect: on the clerk the prompt reads 'Open shop (<store name>)' and letting go opens the shop. The same shop option is not offered twice (no '2 options' for two copies of the same shop).
    """
    When I manually: walk into any 24/7 store
    And I manually: hold Left Alt, aim at the clerk behind the counter, then let go
    Then I confirm: the prompt reads 'Open shop (<store name>)' and letting go opens the shop
    When I manually: hold Left Alt and aim at the counter and the till
    Then I confirm: the same shop option is not offered twice (no '2 options' for two copies of the same shop)

  @kora_target @legacy:tgt-2p-trunk @target:2 @needs:players:2
  Scenario: Trunk opened by targeting shows for others
    """
    Needs 2 testers.
    1. Tester A and B stand behind the same unlocked car.
    2. Tester A opens the trunk with Left Alt (aim at trunk, let go, pick 'Open trunk').
    3. Tester B holds Left Alt and aims at the trunk.
    Expect: Tester B sees the trunk open. B's list shows 'Close trunk' (not 'Open trunk') and B can close it, which A also sees.
    """
    Given a "test_car" is spawned in front of me with keys
    When I manually: ask a second player to stand behind the same unlocked car
    And I manually: hold Left Alt, aim at the trunk, let go and pick 'Open trunk'
    And I manually: ask the second player to hold Left Alt and aim at the trunk
    Then I confirm: the other player sees the trunk open
    And I confirm: the other player's list shows 'Close trunk' (not 'Open trunk')
    When I manually: ask the second player to close the trunk
    Then I confirm: I see the trunk close

  @kora_target @legacy:tgt-2p-block-view @target:2 @needs:players:2
  Scenario: Someone walking through your aim
    """
    Needs 2 testers.
    1. Tester A spawns the umbrella with /testtarget_entity, holds Left Alt and keeps the dot still on it.
    2. Tester B slowly walks between A and the umbrella, then steps away.
    3. Tester A aims at Tester B.
    Expect: A's 'Inspect' prompt goes away while B blocks the view and comes back once B moves (within about a second). Aiming at another player shows no prompt and causes no errors.
    """
    When I run the command "/testtarget_entity"
    And I manually: hold Left Alt and keep the dot still on the umbrella
    And I manually: ask a second player to slowly walk between me and the umbrella, then step away
    Then I confirm: my 'Inspect' prompt goes away while the other player blocks the view
    And I confirm: the 'Inspect' prompt comes back within about a second once they move
    When I manually: aim at the other player
    Then I confirm: no prompt shows when aiming at another player
    And there should be no script errors

  @kora_target @legacy:tgt-debug-outlines @target:1 @checklist @checklist:kora_target:debug-command @cat:core-and-libraries
  Scenario: Show target zone outlines with /kora_target_debug
    """
    1. Go to a 24/7 store or another spot with a shop counter.
    2. Type /kora_target_debug on, then look around. Check F8.
    3. Type /kora_target_debug off. Then type /kora_target_debug banana.
    Expect: 'on' prints 'target zone debug drawing enabled' in F8 and outlines appear around target zones. 'off' prints 'disabled' and removes them. 'banana' prints an 'unrecognised argument' message and changes nothing.
    Also checklist kora_target:debug-command (/koratarget_debug command): Run /koratarget_debug to toggle zone debug drawing (diagnostic). Note: /koratarget_debug was called /kora_target_debug.
    """
    When I manually: go to a 24/7 store or another spot with a shop counter
    And I run the command "/kora_target_debug on"
    And I manually: look around and check F8
    And the F8 console should show "target zone debug drawing enabled"
    Then I confirm: outlines appear around target zones
    When I run the command "/kora_target_debug off"
    And the F8 console should show "disabled"
    Then I confirm: the outlines are removed
    When I run the command "/kora_target_debug banana"
    And the F8 console should show "unrecognised argument"
    Then I confirm: nothing changes

  @kora_target @legacy:tgt-toggle-cmd @target:1
  Scenario: Turn targeting off and on with /testtarget_toggle
    """
    1. Spawn the umbrella with /testtarget_entity.
    2. Type /testtarget_toggle. Check F8.
    3. Hold Left Alt and aim at the umbrella.
    4. Type /testtarget_toggle again and repeat.
    Expect: the first run prints 'target disabled' and holding Alt shows no prompt. The second run prints 'target enabled' and the 'Inspect' prompt works again.
    """
    When I run the command "/testtarget_entity"
    And I run the command "/testtarget_toggle"
    And the F8 console should show "target disabled"
    And I manually: hold Left Alt and aim at the umbrella
    Then I confirm: no prompt shows
    When I run the command "/testtarget_toggle"
    And the F8 console should show "target enabled"
    And I manually: hold Left Alt and aim at the umbrella
    Then I confirm: the 'Inspect' prompt works again

  @kora_target @legacy:tgt-resmon @target:2 @manual
  Scenario: Performance stays low (resmon)
    """
    1. Press F8, type resmon 1 and press Enter.
    2. Find kora_target. Note its CPU ms while not touching Alt.
    3. In a busy spot (gas station or 24/7), hold Left Alt for 20 seconds, moving the aim around over cars, pumps and people.
    4. Let go and watch for 10 seconds. Type resmon 0 to close.
    Expect: about 0.00 ms when Alt is not held. While holding it stays low (well under 0.20 ms) with no FPS drop, and goes back to about 0.00 ms after letting go. Post the numbers you saw.
    """
    When I manually: press F8, type resmon 1 and press Enter
    And I manually: find kora_target and note its CPU ms while not touching Alt
    Then I confirm: CPU is about 0.00 ms when Alt is not held
    When I manually: go to a busy spot (gas station or 24/7) and hold Left Alt for 20 seconds, moving the aim over cars, pumps and people
    Then I confirm: CPU stays well under 0.20 ms while holding with no FPS drop
    When I manually: let go and watch for 10 seconds, then type resmon 0
    Then I confirm: CPU goes back to about 0.00 ms after letting go
    And I confirm: I post the numbers I saw

  @kora_target @legacy:tgt-restart @target:1 @needs:admin
  Scenario: Targeting recovers after a resource restart
    """
    Do this when few players are on. Inventory, fuel, clothing and the HUD depend on kora_target, so a restart can stop them; if anything stays broken, a full server restart fixes it.
    Needs a Mod.
    1. A tester opens a car trunk option list and leaves it open.
    2. The Mod runs /server resource kora_target.
    3. The tester tries Left Alt on a car trunk, a vending machine, a fuel pump and a 24/7 clerk, and checks F8.
    Expect: the open list closes and nothing gets stuck. No errors in F8, and all those options work again without relogging. List anything (shops, fuel, HUD) that stops working.
    """
    Given a "test_car" is spawned in front of me
    When I manually: hold Left Alt at the car trunk, let go and leave the option list open
    And I manually: ask a Mod to run /server resource kora_target
    Then I confirm: the open list closes and nothing gets stuck
    When I manually: try Left Alt on a car trunk, a vending machine, a fuel pump and a 24/7 clerk
    And the F8 console should show no errors
    Then I confirm: all those options work again without relogging
    And I confirm: I list anything (shops, fuel, HUD) that stops working
