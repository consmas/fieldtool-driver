class Endpoints {
  static const login = '/auth/login';
  static const logout = '/auth/logout';
  static const trips = '/trips';
  static String tripDetail(int id) => '/trips/$id';
  static String tripStatus(int id) => '/trips/$id/status';
  static String tripLocations(int id) => '/trips/$id/locations';
  static String tripEvidence(int id) => '/trips/$id/evidence';
  static String tripOdometerStart(int id) => '/trips/$id/odometer/start';
  static String tripOdometerEnd(int id) => '/trips/$id/odometer/end';
  static String tripPreTrip(int id) => '/trips/$id/pre_trip';
  static String tripStops(int id) => '/trips/$id/stops';
  static String tripStop(int tripId, int stopId) => '/trips/$tripId/stops/$stopId';
  static String tripAttachments(int id) => '/trips/$id/attachments';
  static const chatInbox = '/chat/inbox';
  static String tripChat(int tripId) => '/trips/$tripId/chat';
  static String tripChatMessages(int tripId) => '/trips/$tripId/chat/messages';
  static String tripChatMessage(int tripId, int messageId) =>
      '/trips/$tripId/chat/messages/$messageId';
  static const chatConversations = '/chat/conversations';
  static String chatConversation(int id) => '/chat/conversations/$id';
  static String chatConversationMessages(int id) =>
      '/chat/conversations/$id/messages';
  static String chatConversationRead(int id) => '/chat/conversations/$id/read';
}
