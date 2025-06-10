# Jump Button Editor V2 for Roblox

**Customize the on-screen mobile jump button's size and position!**

This script provides a user-friendly graphical interface (GUI) to visually adjust the default mobile jump button in Roblox games. After making adjustments, you can copy a small script snippet to your clipboard, intended for use with Roblox script executors that support an "autoexecute" folder. This allows your jump button customizations to be applied automatically every time you join a game.

**Original by Syshi. V2 inspired by Danechka.**

## Features

*   **Visual Position Adjustment:**
    *   Enable "Drag Mode" to move the jump button around the screen with your finger or mouse.
*   **Visual Size Adjustment:**
    *   Use a slider to easily increase or decrease the size of the jump button.
*   **Precise Size Input:**
    *   A text box allows you to input an exact pixel offset for the jump button's size.
*   **Visual Feedback:**
    *   When "Drag Mode" is enabled, the jump button will have a green border to indicate it's ready to be moved.
*   **Reset Functionality:**
    *   Easily reset the jump button's size and position back to its original state (as it was when the script first ran).
*   **Save for Auto-Execution:**
    *   "Save Changes" button generates a small Lua script.
    *   This script is copied to your clipboard, ready to be pasted into your executor's auto-execute folder.
    *   The generated script applies your saved X, Y, and Size offsets to the jump button.
*   **User-Friendly GUI:**
    *   Draggable window.
    *   Clear labels and controls.
    *   Optional notification system (AkaliNotif) for feedback if the library can be loaded.

## How to Use

1.  **Execute the Script:** Run the "Jump Button Editor V2" script using your preferred Roblox script executor.
2.  **The Editor Window:** A window titled "Jump Button Editor V2" will appear on your screen. You can drag this window by its title bar.
3.  **Adjust Position:**
    *   Click the "**Enable Drag**" button. The button will turn red and its text will change to "Disable Drag".
    *   The on-screen jump button will now have a green border.
    *   Click and drag the actual **Roblox jump button** on your screen to reposition it.
    *   Click "**Disable Drag**" when you're satisfied with the position.
4.  **Adjust Size:**
    *   **Slider:** Drag the nub on the "Size Slider" left or right to decrease or increase the jump button's size.
    *   **Text Input:** Type a numerical value (e.g., `20` for 20 pixels larger, `-10` for 10 pixels smaller) into the text box next to "**Size Offset (px):**" and press Enter or click away. The slider will update to match.
5.  **Reset Changes:**
    *   Click the "**Reset All**" button to revert both the position and size of the jump button to how they were when you first ran the script.
6.  **Save for Auto-Execute:**
    *   Once you're happy with your customizations, click the "**Save Changes**" button.
    *   A small Lua script configured with your current X, Y, and Size offsets will be copied to your computer's clipboard.
    *   You will receive a notification (either a pop-up or text on the button) confirming the script has been copied.
    *   **Manually paste this copied script** into a new `.txt` or `.lua` file within your executor's designated "autoexecute" (or similar) folder.
    *   The next time you start Roblox with your executor, this saved script will run automatically, applying your jump button preferences.

## Target Jump Button Path

This script targets the standard Roblox mobile jump button located at:
`game:GetService("Players").LocalPlayer.PlayerGui.TouchGui.TouchControlFrame.JumpButton`

If the game you are playing uses a custom jump button with a different path, this script will likely not find it, and the editor will show an error or not function correctly for that specific game.

## Dependencies & Executor Requirements

*   **`setclipboard()` function:** Required by your executor for the "Save Changes" feature to copy the script to your clipboard.
*   **`identifyexecutor()` function (Optional):** If available, its output is used for context in the generated script's comments.
*   **`HttpGet` or `game.HttpGet` or `HttpService:HttpGetAsync()`:** One of these must be available in your executor's environment if you want the AkaliNotif notification library to load for better on-screen feedback. If not, the script will fall back to using button text for notifications.
*   **Standard GUI Properties:** The script assumes your executor correctly supports standard Roblox GUI properties like `TextBox.Text`, `UIStroke`, etc.

## Troubleshooting

*   **"Error: JumpBtn Not Found"**:
    *   The game might not be using the default mobile `TouchGui`.
    *   You might be running the script on a PC where `TouchGui` is not enabled by default or is structured differently.
    *   The game might have loaded before the script could access `PlayerGui` elements fully (though `WaitForChild` attempts to mitigate this).
*   **"Save Changes" doesn't copy / No notification library:**
    *   Your executor might not support `setclipboard()`. In this case, the script should `warn` the generated code to your executor's console, where you can manually copy it.
    *   Your executor might block `HttpGet` requests, or the AkaliNotif library URL might be down, preventing the notification system from loading.
*   **Script doesn't work in a specific game:**
    *   The game might have aggressive anti-cheat measures.
    *   The game might use a completely custom UI for its controls.

## Disclaimer

This script is provided for educational and customization purposes. Use it at your own risk. Modifying game clients can sometimes be against a game's Terms of Service. The developers of this script are not responsible for any consequences of its use.

---

Feel free to fork, modify, and improve!
