Uri supportEmailUri({required String subject, required String body}) => Uri(
  scheme: 'mailto',
  path: 'support@prox-us.com',
  query: {'subject': subject, 'body': body}.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&'),
);
