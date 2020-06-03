//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices

class IntroducingPinsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("PINS_MEGAPHONE_TITLE", comment: "Title for PIN megaphone when user doesn't have a PIN")
        bodyText = NSLocalizedString("PINS_MEGAPHONE_BODY", comment: "Body for PIN megaphone when user doesn't have a PIN")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = NSLocalizedString("PINS_MEGAPHONE_ACTION", comment: "Action text for PIN megaphone when user doesn't have a PIN")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let vc = PinSetupViewController.creating { _, error in
                if let error = error {
                    Logger.error("failed to create pin: \(error)")
                } else {
                    // success
                    self?.markAsComplete()
                }
                fromViewController.navigationController?.popToViewController(fromViewController, animated: true) {
                    fromViewController.navigationController?.setNavigationBarHidden(false, animated: false)
                    self?.dismiss(animated: false)
                    self?.presentToast(
                        text: NSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created."),
                        fromViewController: fromViewController
                    )
                }
            }

            fromViewController.navigationController?.pushViewController(vc, animated: true)
        }

        let secondaryButton = snoozeButton(fromViewController: fromViewController) {
            guard RemoteConfig.mandatoryPins else { return MegaphoneStrings.weWillRemindYouLater }

            let daysRemaining = ExperienceUpgradeManager.splashStartDay - experienceUpgrade.daysSinceFirstViewed
            assert(daysRemaining > 0)

            let toastFormat = NSLocalizedString("PINS_MEGAPHONE_SNOOZE_TOAST_FORMAT",
                                    comment: "Toast indication that the user will be reminded later to setup their PIN. Embeds {{time until mandatory}}")

            return String(format: toastFormat, daysRemaining)
        }

        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IntroducingPinsSplash: SplashViewController {
    override var isReadyToComplete: Bool { KeyBackupService.hasMasterKey }

    var ows2FAManager: OWS2FAManager {
        return .shared()
    }

    override var canDismissWithGesture: Bool { return false }

    // MARK: - View lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let heroImageView = UIImageView()
        heroImageView.setImage(imageName: Theme.isDarkThemeEnabled ? "introducing-pins-dark" : "introducing-pins-light")
        if let heroImage = heroImageView.image {
            heroImageView.autoPinToAspectRatio(with: heroImage.size)
        } else {
            owsFailDebug("Missing hero image.")
        }
        view.addSubview(heroImageView)
        heroImageView.autoPinTopToSuperviewMargin(withInset: 10)
        heroImageView.autoHCenterInSuperview()
        heroImageView.setContentHuggingLow()
        heroImageView.setCompressionResistanceLow()

        let title = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_TITLE", comment: "Header for PINs splash screen")
        let body = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_DESCRIPTION", comment: "Body text for PINs splash screen")

        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        // Title label
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperview(withMargin: hMargin)
        // The title label actually overlaps the hero image because it has a long shadow
        // and we want the text to partially sit on top of this.
        titleLabel.autoPinEdge(.top, to: .bottom, of: heroImageView, withOffset: -10)
        titleLabel.setContentHuggingVerticalHigh()

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center
        view.addSubview(bodyLabel)
        bodyLabel.autoPinWidthToSuperview(withMargin: hMargin)
        bodyLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 6)
        bodyLabel.setContentHuggingVerticalHigh()

        // Primary button
        let primaryButton = OWSFlatButton.button(title: primaryButtonTitle(),
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold(),
                                                 titleColor: .white,
                                                 backgroundColor: .ows_accentBlue,
                                                 target: self,
                                                 selector: #selector(didTapPrimaryButton))
        primaryButton.autoSetHeightUsingFont()
        view.addSubview(primaryButton)

        primaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        primaryButton.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: 28)
        primaryButton.setContentHuggingVerticalHigh()

        // Secondary button
        let secondaryButton = UIButton()
        secondaryButton.setTitle(secondaryButtonTitle(), for: .normal)
        secondaryButton.setTitleColor(Theme.accentBlueColor, for: .normal)
        secondaryButton.titleLabel?.font = .ows_dynamicTypeBody
        secondaryButton.addTarget(self, action: #selector(didTapSecondaryButton), for: .touchUpInside)
        view.addSubview(secondaryButton)

        secondaryButton.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
        secondaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        secondaryButton.autoPinEdge(.top, to: .bottom, of: primaryButton, withOffset: 15)
        secondaryButton.setContentHuggingVerticalHigh()
    }

    @objc
    func didTapPrimaryButton(_ sender: UIButton) {
        let vc = PinSetupViewController.creating { [weak self] _, _ in
            self?.dismiss(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc
    func didTapSecondaryButton(_ sender: UIButton) {
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
        present(vc, animated: true, completion: nil)
    }

    func primaryButtonTitle() -> String {
        return NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_CREATE_BUTTON",
                                 comment: "Button to start a create pin flow from the one time splash screen that appears after upgrading")
    }

    func secondaryButtonTitle() -> String {
        return CommonStrings.learnMore
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let fromViewController = presentingViewController else {
            return owsFailDebug("Trying to dismiss while not presented.")
        }

        super.dismiss(animated: flag) { [weak self] in
            if let self = self, !self.isDismissWithoutCompleting {
                self.presentToast(
                    text: NSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created."),
                    fromViewController: fromViewController
                )
            }
            completion?()
        }
    }
}
