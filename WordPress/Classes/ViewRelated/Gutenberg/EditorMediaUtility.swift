import Aztec
import Gridicons

extension Operation: CancellableTask {}

final class ImageDownload: AsyncOperation {
    let url: URL
    let blog: Blog
    private let onSuccess: (UIImage) -> ()
    private let onFailure: (Error) -> ()

    init(url: URL, blog: Blog, onSuccess: @escaping (UIImage) -> (), onFailure: @escaping (Error) -> ()) {
        self.url = url
        self.blog = blog
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    override func main() {
        let mediaRequestAuthenticator = MediaRequestAuthenticator()

        mediaRequestAuthenticator.authenticatedRequest(
            for: url,
            blog: blog,
            onComplete: { request in
                ImageDownloader.shared.downloadImage(for: request) { [weak self] (image, error) in
                    guard let self = self else {
                        return
                    }
                    
                    self.state = .isFinished
                    
                    DispatchQueue.main.async {
                        guard let image = image else {
                            DDLogError("Unable to download image for attachment with url = \(String(describing: request.url)). Details: \(String(describing: error?.localizedDescription))")
                            if let error = error {
                                self.onFailure(error)
                            } else {
                                self.onFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
                            }
                            
                            return
                        }

                        self.onSuccess(image)
                    }
                }
        },
            onFailure: { error in
                self.state = .isFinished
                self.onFailure(error)
        })
    }
}

protocol CancellableTask {
    func cancel()
}

extension URLSession: CancellableTask {
    func cancel() {
        invalidateAndCancel()
    }
}

class EditorMediaUtility {

    private struct Constants {
        static let placeholderDocumentLink = URL(string: "documentUploading://")!
    }

    func placeholderImage(for attachment: NSTextAttachment, size: CGSize, tintColor: UIColor?) -> UIImage {
        var icon: UIImage
        switch attachment {
        case let imageAttachment as ImageAttachment:
            if imageAttachment.url == Constants.placeholderDocumentLink {
                icon = .gridicon(.pages, size: size)
            } else {
                icon = .gridicon(.image, size: size)
            }
        case _ as VideoAttachment:
            icon = .gridicon(.video, size: size)
        default:
            icon = .gridicon(.attachment, size: size)
        }
        if #available(iOS 13.0, *), let color = tintColor {
            icon = icon.withTintColor(color)
        }
        icon.addAccessibilityForAttachment(attachment)
        return icon
    }

    func fetchPosterImage(for sourceURL: URL, onSuccess: @escaping (UIImage) -> (), onFailure: @escaping () -> ()) {
        let thumbnailGenerator = MediaVideoExporter(url: sourceURL)
        thumbnailGenerator.exportPreviewImageForVideo(atURL: sourceURL, imageOptions: nil, onCompletion: { (exportResult) in
            guard let image = UIImage(contentsOfFile: exportResult.url.path) else {
                onFailure()
                return
            }
            DispatchQueue.main.async {
                onSuccess(image)
            }
        }, onError: { (error) in
            DDLogError("Unable to grab frame from video = \(sourceURL). Details: \(error.localizedDescription)")
            onFailure()
        })
    }


    func downloadImage(
        from url: URL,
        post: AbstractPost,
        success: @escaping (UIImage) -> Void,
        onFailure failure: @escaping (Error) -> Void) -> CancellableTask {

        let imageMaxDimension = max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height)
        //use height zero to maintain the aspect ratio when fetching
        let size = CGSize(width: imageMaxDimension, height: 0)
        let scale = UIScreen.main.scale

        return downloadImage(from: url, size: size, scale: scale, post: post, success: success, onFailure: failure)
    }

    func downloadImage(
        from url: URL,
        size requestSize: CGSize,
        scale: CGFloat, post: AbstractPost,
        success: @escaping (UIImage) -> Void,
        onFailure failure: @escaping (Error) -> Void) -> CancellableTask { //}-> ImageDownloader.Task {

        let imageMaxDimension = max(requestSize.width, requestSize.height)
        //use height zero to maintain the aspect ratio when fetching
        var size = CGSize(width: imageMaxDimension, height: 0)
        let requestURL: URL

        if url.isFileURL {
            requestURL = url
        } else if post.blog.isHostedAtWPcom && post.blog.isPrivate() && url.isHostedAtWPCom() {
            // private wpcom image needs special handling.
            // the size that WPImageHelper expects is pixel size
            size.width = size.width * scale
            requestURL = WPImageURLHelper.imageURLWithSize(size, forImageURL: url)
        } else if !post.blog.isHostedAtWPcom && post.blog.isBasicAuthCredentialStored() {
            size.width = size.width * scale
            requestURL = WPImageURLHelper.imageURLWithSize(size, forImageURL: url)
        } else {
            // the size that PhotonImageURLHelper expects is points size
            requestURL = PhotonImageURLHelper.photonURL(with: size, forImageURL: url)
        }

        let imageDownload = ImageDownload(
            url: requestURL,
            blog: post.blog,
            onSuccess: success,
            onFailure: failure)
        
        imageDownload.start()
        return imageDownload
        
        
        /*
        let operationQueue = OperationQueue()
        
        operationQueue.addOperation(<#T##op: Operation##Operation#>)
        
        // NUEVO CODIGO

        let mediaRequestAuthenticator = MediaRequestAuthenticator()

        mediaRequestAuthenticator.authenticatedRequest(
            for: requestURL,
            blog: post.blog,
            onComplete: { request in
                // aca deberia llamarse el  request...
        },
            onFailure: { error in
                failure(error)
        })

        // VIEJO CODIGO
        let task = ImageDownloader.shared.downloadImage(for: request) { [weak self] (image, error) in
            guard let _ = self else {
                return
            }

            DispatchQueue.main.async {
                guard let image = image else {
                    DDLogError("Unable to download image for attachment with url = \(url). Details: \(String(describing: error?.localizedDescription))")
                    if let error = error {
                        failure(error)
                    } else {
                        failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil))
                    }
                    return
                }

                success(image)
            }
        }
        
        return task
         */
    }

    static func fetchRemoteVideoURL(for media: Media, in post: AbstractPost, completion: @escaping ( Result<(videoURL: URL, posterURL: URL?), Error> ) -> Void) {
        guard let videoPressID = media.videopressGUID else {
            //the site can be a self-hosted site if there's no videopressGUID
            if let videoURLString = media.remoteURL,
                let videoURL = URL(string: videoURLString) {
                completion(Result.success((videoURL: videoURL, posterURL: nil)))
            } else {
                DDLogError("Unable to find remote video URL for video with upload ID = \(media.uploadID).")
                completion(Result.failure(NSError()))
            }
            return
        }
        let mediaService = MediaService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        mediaService.getMediaURL(fromVideoPressID: videoPressID, in: post.blog, success: { (videoURLString, posterURLString) in
            guard let videoURL = URL(string: videoURLString) else {
                completion(Result.failure(NSError()))
                return
            }
            var posterURL: URL?
            if let validPosterURLString = posterURLString, let url = URL(string: validPosterURLString) {
                posterURL = url
            }
            completion(Result.success((videoURL: videoURL, posterURL: posterURL)))
        }, failure: { (error) in
            DDLogError("Unable to find information for VideoPress video with ID = \(videoPressID). Details: \(error.localizedDescription)")
            completion(Result.failure(error))
        })
    }
}
