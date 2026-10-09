export function referralProfileComplete(data: FirebaseFirestore.DocumentData): boolean {
  const text = (value: unknown) => typeof value === 'string' && value.trim().length > 0;
  const keyword = (keys: string[]) => keys.some(key => {
    const values = data[key] || data.keywords?.[key] || data.keywordGroups?.[key];
    return Array.isArray(values) && values.some(text);
  });
  return text(data.displayName || data.name || data.alias) &&
    text(data.selfieUrl || data.photoUrl || data.photoURL) &&
    keyword(['searchingForKeywords', 'searchingFor', 'SearchingFor', 'Searching For', 'searching_for']) &&
    keyword(['canProvideKeywords', 'canProvide', 'CanProvide', 'Can Provide', 'can_provide']);
}
