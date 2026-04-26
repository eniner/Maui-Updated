# maui

UI for MuleAssist macro written in Lua using Imgui.

## Installation

Copy the `maui` folder into the MQ `lua` folder.

## Usage

Start the UI with `/lua run maui`.

## Examples

Navigate between INI sections from the left menu. Sections which can be enabled or disabled in the INI will be either green or red to indicate whether they are enabled or disabled.

![](images/general.png)

The INI file content can be edited directly by selecting `Raw INI` from the left menu. Note the separate save buttons when editing the raw INI.

![](images/rawINItab.png)

Spells which have upgraded versions available in the spellbook will have an upgrade button when they are selected.

![](images/spellupgrade.png)

Right clicking a button will open a context menu to select a spell, AA or disc.

![](images/spellpicker.png)

