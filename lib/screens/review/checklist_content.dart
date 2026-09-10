typedef ReviewStep = ({String title, String detail});

const testerMissionSteps = <ReviewStep>[
  (
    title: 'Create a useful profile',
    detail:
        'Add at least one Looking For and one Can Provide keyword, save, and reopen the profile to verify it.',
  ),
  (
    title: 'Try nearby discovery',
    detail:
        'Choose a radius and matching mode. Verify loading, an empty result, and a real nearby result when another tester is available.',
  ),
  (
    title: 'Request and accept a meetup',
    detail:
        'Use two tester accounts. Confirm both phones see the same request and acceptance.',
  ),
  (
    title: 'Coordinate in chat',
    detail:
        'Send a short message, agree on a public meeting point, and verify the message arrives on the other phone.',
  ),
  (
    title: 'Complete and rate a meetup',
    detail:
        'Confirm arrival, complete the meetup on both phones, and submit feedback once.',
  ),
  (
    title: 'Check privacy controls',
    detail:
        'With a consenting tester, block an account, reopen Blocked users, then unblock it. Check Party profile sharing.',
  ),
  (
    title: 'Test an interrupted connection',
    detail:
        'Temporarily turn off connectivity, create a support draft, reopen it, reconnect, and submit once.',
  ),
  (
    title: 'Send your observations',
    detail:
        'Open Support & feedback. Include the app version, phone model, steps, and whether you used Android or iOS.',
  ),
];

const releaseReviewSteps = <ReviewStep>[
  (
    title: 'Compare installed versions',
    detail:
        'Check About on Android and iOS. Confirm both are on the intended version and supported release channel.',
  ),
  (
    title: 'Verify required update behavior',
    detail:
        'Use the release test configuration. Confirm an old version cannot enter the app; the update action opens the correct platform distribution page.',
  ),
  (
    title: 'Verify optional updates and recovery',
    detail:
        'Confirm a current build opens normally, an optional update can be deferred, and update checks recover after reconnecting.',
  ),
  (
    title: 'Run the complete tester mission',
    detail:
        'Complete profile, discovery, request, chat, meetup, rating, blocking, and support on both operating systems.',
  ),
  (
    title: 'Test permission choices',
    detail:
        'Try allow, deny, and permanently deny for location and notifications. Verify a useful recovery action appears.',
  ),
  (
    title: 'Check readability and navigation',
    detail:
        'Use large system text, a screen reader, a narrow phone, keyboard entry, back navigation, and light/dark system appearance.',
  ),
  (
    title: 'Verify account isolation',
    detail:
        'Sign out and use a second account. Verify the previous account’s chats, private records, and notifications are not shown.',
  ),
  (
    title: 'Verify purchases and restore',
    detail:
        'Use the platform billing sandbox when configured. Confirm canceled or failed payments never grant an item. A sample screen must not charge or grant access.',
  ),
  (
    title: 'Verify restricted Pro preview',
    detail:
        'Confirm live Pro preview remains limited to the approved account and other accounts can only use labeled local examples.',
  ),
  (
    title: 'Record device evidence',
    detail:
        'Attach device models, OS/app versions, screenshots, and unresolved issues to the release review. This checklist alone is not automated verification or release approval.',
  ),
];

const presenceRehearsalSteps = <ReviewStep>[
  (
    title: 'Choose your matching intent',
    detail:
        'In your profile, add what you are Looking For and what you Can Provide. Save your changes.',
  ),
  (
    title: 'Check location permission',
    detail:
        'Open Location & privacy in Settings. Enable location when using Prox if you want nearby results.',
  ),
  (
    title: 'Choose your radius',
    detail:
        'Open Match settings and pick an appropriate distance. A larger radius may produce results farther away.',
  ),
  (
    title: 'Practice availability',
    detail:
        'Try Active while ready for a meetup, and return to Passive when you finish. Review any Active commitment before confirming.',
  ),
  (
    title: 'Review sharing',
    detail:
        'Open Party profile sharing and choose which profile details mutual Party members may see.',
  ),
];
