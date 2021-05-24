# Translations

## For Developers

### Localize User Facing Strings

Use the NSLocalizedString macros to mark any user-facing strings as
localizable. See existing usages of this macro for examples.

### Extract Source Strings

To extract the latest translatable strings and comments from our local source
files into our English localization file:

    bin/auto-genstrings

At this point you should see your new strings, untranslated in only the English
(en) localization.

Edit Signal/translations/en.lproj/Localizable.strings to translate your strings.

Commit these English translations with your work. Do not touch the non-English
localizations. Those are updated as part of our release process by Signal
Staff.

### Writing Good Translatable Strings

Be sure to include comments in your translations, and enforce that other
contributors do as well.  Why comment? For example, in English these are
the same, but in Finnish the noun/verb are distinct.

#### English

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Archive"
    
    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Archive"

#### Finnish

    /* Tab button label which takes you to view all your archived conversations */
    ARCHIVE_HEADER="Arkisto"

    /* Button label to archive the current conversation */
    ARCHIVE_ACTION="Arkistoi"

Context should also provide a hint as to how much text should be
provided. For example, is it an alert title, which can be a few words, a
button, which must be *very* short, or an alert message, which can be a
little longer?

## For Maintainers (Signal Staff)

Translations are solicited on Transifex[https://www.transifex.com/signalapp/signal-ios/]. We
upload our source language (US English) to Transifex, where our
translators can submit their translations. Before the app is released,
we pull their latest work into the codebase.

## Fetch Translations

Generally, you want to fetch the latest translations whenever releasing. The
exception is if you have recently changed lots of existing source strings 
that haven't had a chance to be translated.

To fetch the latest translations:

    bin/pull-translations

This imposes some limits on what localizations we include. For example,
we don't want to include languages until a substantial portion of the
app has been translated.

Sometimes you'll pull down a translation which isn't yet tracked by git.
This means that translation recently became sufficiently complete to
include in the project. As well as adding it to git, you need to update
the Xcode project to include the new localization.

### Upload Strings to be Translated

Make new source strings available to our translators by uploading them
to Transifex. Immediately after uploading we also need to pull down the 
updated translations. Granted, at this point, the new strings will be in 
English until translated, but English is preferable to the string name 
like ARCHIVE_HEADER which we'd otherwise see.

To push the new source strings and then fetch the resultant translations:

    bin/sync-translations

