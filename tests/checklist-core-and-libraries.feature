# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_target — Core & Libraries

  @kora_target @checklist @checklist:kora_target:option-menu @cat:core-and-libraries @manual
  Scenario: Select an option from the target menu
    """
    Checklist test: While aiming at a target, click (or scroll then click) an option; onSelect runs; Escape/Backspace/right-click cancel.
    """
    When I manually: hold Left Alt, aim at a target with several options and release Alt
    And I manually: scroll then click an option
    Then I confirm: the option's action runs
    When I manually: open the list again and press Escape, then Backspace, then right-click
    Then I confirm: each of Escape, Backspace and right-click cancels the list without running an option

  @kora_target @checklist @checklist:kora_target:zone-targets @cat:core-and-libraries @manual
  Scenario: Zone and entity targets work
    """
    Checklist test: Walk to box/sphere zones (depot, scrapyard, shops, houses) and entities; options appear within their distance, hidden when too far.
    """
    When I manually: walk to box/sphere zones (depot, scrapyard, shops, houses) and entities and hold Left Alt aiming at them
    Then I confirm: options appear within their distance
    And I confirm: options are hidden when I am too far away

  @kora_target @checklist @checklist:kora_target:focus-recovery @cat:core-and-libraries
  Scenario: Stuck-target recovery
    """
    Checklist test: Alt+Tab or open the pause menu while targeting: the eye cancels; /target-reset force-clears a stuck state.
    """
    When I manually: hold Left Alt to start targeting, then Alt+Tab out and back
    Then I confirm: the eye cancels
    When I manually: hold Left Alt to start targeting, then open the pause menu
    Then I confirm: the eye cancels
    When I run the command "/target-reset"
    Then I confirm: any stuck targeting state is force-cleared

  @kora_target @checklist @checklist:kora_target:compat-ox-qb @cat:core-and-libraries
  Scenario: qb-target / ox_target compatibility
    """
    Checklist test: Resources using exports['qb-target'] or exports.ox_target add boxes/entities/models and they show up with icons and labels.
    """
    Given a "prop" prop is spawned in front of me
    When I manually: walk to a place where a script has registered qb-target or ox_target boxes, entities or models (for example a shop, ATM, fuel pump or vending machine)
    And I manually: hold Left Alt and aim at each target
    Then I confirm: each target shows up with its icon and label
