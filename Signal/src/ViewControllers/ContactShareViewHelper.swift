//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ContactsUI
import MessageUI

@objc
public protocol ContactShareViewHelperDelegate: class {
    func didCreateOrEditContact()
}

@objc
public class ContactShareViewHelper: NSObject, CNContactViewControllerDelegate {

    weak var delegate: ContactShareViewHelperDelegate?

    let contactsManager: OWSContactsManager

    public required init(contactsManager: OWSContactsManager) {
        SwiftAssertIsOnMainThread(#function)

        self.contactsManager = contactsManager

        super.init()
    }

    // MARK: Actions

    @objc
    public func sendMessage(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .compose, contactShare: contactShare, fromViewController: fromViewController)
    }

    @objc
    public func audioCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .audioCall, contactShare: contactShare, fromViewController: fromViewController)
    }

    @objc
    public func videoCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .videoCall, contactShare: contactShare, fromViewController: fromViewController)
    }

    private func presentThreadAndPeform(action: ConversationViewAction, contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        // TODO: We're taking the first Signal account id. We might
        // want to let the user select if there's more than one.
        let phoneNumbers = contactShare.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) missing Signal recipient id.")
            return
        }
        guard phoneNumbers.count > 1 else {
            let recipientId = phoneNumbers.first!
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, fromViewController: fromViewController, completion: { (recipientId) in
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
        })
    }

    @objc
    public func inviteContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("\(logTag) Device cannot send text")
            OWSAlerts.showErrorAlert(message: NSLocalizedString("UNSUPPORTED_FEATURE_ERROR", comment: ""))
            return
        }
        let phoneNumbers = contactShare.e164PhoneNumbers()
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) no phone numbers.")
            return
        }

        let inviteFlow =
            InviteFlow(presentingViewController: fromViewController, contactsManager: contactsManager)
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    func addToContacts(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressCreateNewContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressAddToExistingContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSAlerts.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], fromViewController: UIViewController, completion :@escaping ((String) -> Void)) {

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for phoneNumber in phoneNumbers {
            actionSheet.addAction(UIAlertAction(title: PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber),
                                                          style: .default) { _ in
                                                            completion(phoneNumber)
            })
        }
        actionSheet.addAction(OWSAlerts.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    func didPressCreateNewContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        presentNewContactView(contactShare: contactShare, fromViewController: fromViewController)
    }

    func didPressAddToExistingContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("\(logTag) \(#function)")

        presentSelectAddToExistingContactView(contactShare: contactShare, fromViewController: fromViewController)
    }

    // MARK: -

    private func presentNewContactView(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        var convertedSystemContact: CNContact?
        OWSPrimaryStorage.shared().newDatabaseConnection().read({ (transaction) in
            convertedSystemContact = contactShare.convertToSystemContact(transaction: transaction)
        })

        guard let systemContact = convertedSystemContact else {
            owsFail("\(logTag) Could not derive system contact.")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: fromViewController)
            return
        }

        let contactViewController = CNContactViewController(forNewContact: systemContact)
        contactViewController.delegate = self
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton, style: .plain, target: self, action: #selector(didFinishEditingContact))
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                                                 style: .plain,
                                                                                 target: self,
                                                                                 action: #selector(didFinishEditingContact))

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        navigationController.pushViewController(contactViewController, animated: true)

        // HACK otherwise CNContactViewController Navbar is shown as black.
        // RADAR rdar://28433898 http://www.openradar.me/28433898
        // CNContactViewController incompatible with opaque navigation bar
        UIUtil.applyDefaultSystemAppearence()
    }

    private func presentSelectAddToExistingContactView(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: fromViewController)
            return
        }

        // TODO: Revisit this.
        guard let firstPhoneNumber = contactShare.e164PhoneNumbers().first else {
            owsFail("\(logTag) Missing phone number.")
            return
        }

        // TODO: We need to modify OWSAddToContactViewController to take a OWSContact
        // and merge it with an existing CNContact.
        let viewController = OWSAddToContactViewController()
        viewController.configure(withRecipientId: firstPhoneNumber)

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - CNContactViewControllerDelegate

    @objc public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("\(logTag) \(#function)")

        guard let delegate = delegate else {
            owsFail("\(logTag) missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }

    @objc public func didFinishEditingContact() {
        Logger.info("\(logTag) \(#function)")

        guard let delegate = delegate else {
            owsFail("\(logTag) missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }
}
