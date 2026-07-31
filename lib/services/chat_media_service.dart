import "package:image_picker/image_picker.dart";

class ChatMediaService {
  ChatMediaService._();
  static final ChatMediaService instance = ChatMediaService._();

  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takePhoto() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  }

  Future<XFile?> pickFromGallery() {
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  }

  Future<String> uploadChatImage({
    required String chatId,
    required XFile file,
  }) async {
    return file.path;
  }

  Future<String> uploadChatImageBytes({
    required String chatId,
    required List<int> bytes,
    String fileName = "chat-image.jpg",
  }) async {
    return fileName;
  }
}
