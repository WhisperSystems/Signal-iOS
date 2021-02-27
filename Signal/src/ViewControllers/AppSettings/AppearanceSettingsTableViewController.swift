//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AppearanceSettingsTableViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings.")

        self.useThemeBackgroundColors = true

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .ThemeDidChange,
            object: nil
        )
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let firstSection = OWSTableSection()
        firstSection.customHeaderHeight = 14

        // Starting with iOS 13, show them in appearance section to allow setting the app
        // theme to match the "system" dark/light mode settings..
        if #available(iOS 13, *) {
            firstSection.add(OWSTableItem.disclosureItem(
                withText: NSLocalizedString("SETTINGS_APPEARANCE_THEME_TITLE",
                                            comment: "The title for the theme section in the appearance settings."),
                detailText: ThemeSettingsTableViewController.currentThemeName,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "theme")
            ) { [weak self] in
                guard let self = self else { return }
                let vc = ThemeSettingsTableViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            })
        }

        firstSection.add(OWSTableItem.disclosureItem(
            withText: NSLocalizedString("SETTINGS_ITEM_WALLPAPER",
                                        comment: "Label for settings view that allows user to change the wallpaper."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = WallpaperSettingsViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        })

        contents.addSection(firstSection)

        let contactSection = OWSTableSection()
        contactSection.customHeaderHeight = 14
        contactSection.footerTitle = NSLocalizedString(
            "SETTINGS_APPEARANCE_AVATAR_FOOTER",
            comment: "Footer for avatar section in appearance settings")

        contactSection.add(
            OWSTableItem.switch(
                withText: NSLocalizedString(
                    "SETTINGS_APPEARANCE_AVATAR_PREFERENCE_LABEL",
                    comment: "Title for switch to toggle preference between contact and profile avatars"),
                isOn: {
                    SDSDatabaseStorage.shared.read { SSKPreferences.preferContactAvatars(transaction: $0) }
                },
                target: self,
                selector: #selector(didToggleAvatarPreference(_:))
            )
        )

        contents.addSection(contactSection)
        
        let avaterSection = OWSTableSection()
        avaterSection.customHeaderHeight = 14
        avaterSection.footerTitle = NSLocalizedString(
            "SETTINGS_APPEARANCE_GROUP_AVATARS_FOOTER",
            comment: "Footer for group chat avatar section in appearance settings")

        avaterSection.add(
            OWSTableItem.switch(
                withText: NSLocalizedString(
                    "SETTINGS_APPEARANCE_GROUP_AVATARS_PREFERENCE_LABEL",
                    comment: "Title for switch to toggle preference of whether to show profile pictures in group chat"),
                isOn: {
                    SDSDatabaseStorage.shared.read { SSKPreferences.hideGroupChatAvatars(transaction: $0) }
                },
                target: self,
                selector: #selector(didToggleGroupAvatarsPreference(_:))
            )
        )

        contents.addSection(avaterSection)

        // TODO iOS 13 – maybe expose the preferred language settings here to match android
        // It not longer seems to exist in iOS 13.1 so not sure if Apple got rid of it
        // or it has just temporarily been disabled.

        self.contents = contents
    }

    func appearanceItem(_ mode: ThemeMode) -> OWSTableItem {
        return OWSTableItem(
            text: nameForTheme(mode),
            actionBlock: { [weak self] in
                self?.changeTheme(mode)
            },
            accessoryType: Theme.getOrFetchCurrentTheme() == mode ? .checkmark : .none
        )
    }

    func changeTheme(_ mode: ThemeMode) {
        Theme.setCurrent(mode)
        updateTableContents()
    }

    var currentThemeName: String {
        return nameForTheme(Theme.getOrFetchCurrentTheme())
    }

    func nameForTheme(_ mode: ThemeMode) -> String {
        switch mode {
        case .dark:
            return NSLocalizedString("APPEARANCE_SETTINGS_DARK_THEME_NAME", comment: "Name indicating that the dark theme is enabled.")
        case .light:
            return NSLocalizedString("APPEARANCE_SETTINGS_LIGHT_THEME_NAME", comment: "Name indicating that the light theme is enabled.")
        case .system:
            return NSLocalizedString("APPEARANCE_SETTINGS_SYSTEM_THEME_NAME", comment: "Name indicating that the system theme is enabled.")
        }
    }

    @objc func didToggleAvatarPreference(_ sender: UISwitch) {
        Logger.info("Avatar preference toggled: \(sender.isOn)")
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            SSKPreferences.setPreferContactAvatars(sender.isOn, transaction: writeTx)
        }

    }
    
    @objc func didToggleGroupAvatarsPreference(_ sender: UISwitch) {
        Logger.info("Group Avatar preference toggled: \(sender.isOn)")
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            SSKPreferences.setHideGroupChatAvatars(sender.isOn, transaction: writeTx)
        }
    }
    
    
}
