> NOTE: This document may become out of date. Check the last updated date.

# Building

DataDelve was first built exclusively in Roblox Studio, so the workflow for developing this plugin is centered around Studio. All the UI is manually made with instances.

To build a copy of the plugin, you must first have Lune installed. DataDelve uses [Rokit](https://github.com/rojo-rbx/rokit) as the toolchain manager. Once you have Rokit installed, use this command to install Lune as well as the other tools:

```bash
rokit install
```

You can also install Lune by other means if you don't want to use Rokit (https://lune-org.github.io/docs/getting-started/1-installation).

Here is a quick guide to using Lune:

```bash
# See list of Lune scripts for this project.
lune list
# Run a Lune script
lune run [script name]
```

To build the plugin, run this command:
```bash
# Build for development
lune run build my_test_build
# Build for release
lune run build my_test_build -- --release
```

This will create a file called `my_test_build.rbxm` in the `build` directory. You can then install the plugin by adding it to your local plugins directory or by dragging it into Studio, right clicking, and pressing `Save as Local Plugin`. You can begin making modifications to the plugin with this file as well (make sure you built for development).

If you would like to work with DataDelve using Rojo or another syncing tool, you can use those too. You have to manually set up the project files, though. I couldn't get it to work, so I gave up, but if you can get it to work, a contribution with those files would be appreciated.

# Syncing

Use the `sync` Lune script to sync. Here is how to use it:
```bash
# Enjoyable mode (has artifical pauses to improve viewing experience)
lune run sync [path_to_plugin_file]
# Fast mode
lune run sync [path_to_plugin_file] -- --fastMode
```

This will sync the directory up with the provided plugin file. You can sync directly with the plugin file in your local plugins folder.

# Development Workflow

This is the workflow I use which you can use if you want:
1. Make changes in Studio.
2. Export the plugin to a file.
3. Run the sync script on that file.
4. Run StyLua.
5. Commit changes.

The build script is just for bootstrapping the process and making release builds.

# Running and writing tests
Most of the tests in DataDelve are done manually, but I have also included some automatic ones for peace of mind.

To run the tests, build the plugin in development mode so the tests are included, then run the plugin. If there are no errors then the tests ran successfuly. To add a test, add a script in the `tests` folder and have it error if something goes wrong. Note that tests may be affected by global state such as the settings.

# Overview of Directory Structure
The directory structure is just for easy browsing and does not reflect the structure of the `.rbxmx` of the plugin.

- `assets/` contains `.rbxmx` files of all the UI instances used.
- `tests/` contains tests that are ran when the plugin starts.
- `src/` contains all the source code.

<br>
<hr>
<br>

# Overview of Plugin Structure

The codebase is kind of a mess, but here is a brief overview to help you figure it out.

> Consult this section when necessary.

## Rough diagram of information flow
```mermaid
flowchart TD
    B[App] -->|Requests| C[Session & Pages]
    C -->|Requests| D[DataStoreService]
    A[UI & Views] -->|Events| B
    B -->|State Changes| A
    D -.->|Errors| C
    C -.->|Errors| B
    B -.->|Errors| C2[UIMessages]
    B -.->|Errors| A
    B -->|Data| E[Viewer]
    E -.->|Errors| C2
```

## Entry Point/App
The entry point is the script called `main`. It interfaces with an `App` object by enabling and disabling it. The `App` object does all the main stuff. Each `App` object has its own ID which is used in case in the future multiple instances of the plugin should be started (like if tab tearing is ever added).

The two apps are currently `App` and `ClientFallbackApp`.

`ClientFallbackApp` appears when the user tries to use the plugin in a play test on the client.

## DataStore Interface
The main interfaces for DataStores are `Session` and `Pages`. Each app has its own Session object which stores state about what DataStore/key/version is being viewed and is used to send requests.

## UI
DataDelve handles UI in an imperative manner.

The main app creates an instance of the `UI` object. It also creates an instance of the `UIMessages` object. `UIMessages` is used to send toasts and alerts. `UI` sets up the UI and has an assortment of convenience functions for manipulating it. Right now `App` and `UI` are tightly coupled.

### Theming
A `Theme` object contains all the colors used in the UI. It has an event to listen to when the color changes. Every StyleState is passed a `Theme` object so it knows how to style itself. The `Theme` object also contains asset IDs for icons. All icons in the code are slowly being moved into here.

### StyleState
This is what I decided to call my components. StyleStates are objects that wrap around Roblox UI instances with extra state so it knows how to style it. For example, `TextBoxStyleState` has extra state about an errors in the input so it knows to display as red. There is a type definition for StyleStates in `UI.StyleState.StyleStateHelper`. Every StyleState has an `#update(speed)` function which will update the UI based on its state at the given speed using `TweenService`.

> NOTE: If a StyleState is updated multiple times in a single frame, there may be styling errors because `TweenService` will not pick the latest tween to play. All StyleStates should use the `#tween` function in `StyleStateHelper` which will have a fix for this in the future (if I feel like it). You may also see random `task.wait()/task.delay(0, ...)` in the code for this reason.

When you want to listen to an event on a StyleState, if the underlying object already has that event, it will be in the object which you can access by looking at the source of the StyleState (usually its in a field called `button/textBox/frame`). For example, to see if `ButtonStyleState` was clicked, you do 
```lua
buttonStyleState.button.Activated:Connect(...)
```

If the event is a custom one, it will be in the StyleState:

```lua
checkboxStyleState.toggled:Connect(...)
```

StyleStates do not have a `new` function. You have to construct them from an already existing UI object using `from`. Most of the new StyleStates have types so you know what the UI object should be like, but the old one's don't, so you'll just have to figure it out.

### StyleState Tree
> NOTE: When accessing/passing around a UI object, try to access/pass it from it's StyleState. This is because you can get the object from the StyleState, but you can't get the StyleState from the object.

When working with StyleStates, I usually put them into a tree to reflect the structure of the UI. In the `UI` ModuleScript you will see a giant tree called `styleStates`. It's where I instantiated most of my StyleStates so I can access them easily. When the theme is changed, the UI object will traverse this tree and call `#update("slow")` on them. A consequence of this is that StyleStates outside the main UI tree will not update when the theme is updated. You can wrap an isolated StyleState tree with the `UI.StyleState.StyleStateWrapper` object to make sure it follows the theme.

### Utility StyleStates
`UI.StyleState.Utilities` contains some utility StyleStates. These don't go in any trees because they are usually only used for modals or short-lived UI effects (loading bar, skeleton effect).

### Viewers
Viewers are used to view JSON data. Every `App` has exactly one (this will change once tabs are added). There is only one viewer right now (the tree one).

### Views
You can see there some module scripts that end in `View` inside `UI` (e.g `VersionsView`, `OrderedDataStoreView`). This is when the `UI` ModuleScript was getting too big, and I decided to stop adding to it. They are basically their only mini `UI`, but only concerned with a single part of the UI. They also have a `#reset` method which is called to reset them to their original state if the user re-opens them with different data.

### The Views Refactor
I am planning on splitting everything into views to decouple the UI code more. Views will also go from `#from` and `#reset` to `#new` and `#destroy`. This is so multiple can be created for one `App` which will help with implementing tabs.

## Assets
In `UI` there is a folder called `Assets` which has all the Gui objects used by the `UI` object. Other scripts may have their own assets stored within as well.

## Settings
Settings contains global state for all the settings the user configured.

# Conclusion
This is just a brief overview of how I structured the plugin. If you have any questions you can't figure out, feel free to send me a message on the Roblox DevForum!
