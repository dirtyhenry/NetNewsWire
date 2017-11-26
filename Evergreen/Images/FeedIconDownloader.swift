//
//  FeedIconDownloader.swift
//  Evergreen
//
//  Created by Brent Simmons on 11/26/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Cocoa
import Data
import RSWeb
import RSParser

public final class FeedIconDownloader {

	private let imageDownloader: ImageDownloader
	private var homePageToIconURLCache = [String: String]()

	init(imageDownloader: ImageDownloader) {

		self.imageDownloader = imageDownloader
	}

	func icon(for feed: Feed) -> NSImage? {

		if let iconURL = feed.iconURL {
			return icon(forURL: iconURL)
		}

		if let homePageURL = feed.homePageURL {
			return icon(forHomePageURL: homePageURL)
		}

		return nil
	}

	func icon(forHomePageURL homePageURL: String) -> NSImage? {

		if let iconURL = cachedIconURL(for: homePageURL) {
			return icon(forURL: iconURL)
		}
		
		findIconURLForHomePageURL(homePageURL)
		return nil
	}

	func icon(forURL url: String) -> NSImage? {

		return imageDownloader.image(for: url)
	}
}

private extension FeedIconDownloader {

	func cachedIconURL(for homePageURL: String) -> String? {

		return homePageToIconURLCache[homePageURL]
	}

	func cacheIconURL(for homePageURL: String, _ iconURL: String) {

		homePageToIconURLCache[homePageURL] = iconURL
	}

	func findIconURLForHomePageURL(_ homePageURL: String) {

		guard let url = URL(string: homePageURL) else {
			return
		}

		downloadUsingCache(url) { (data, response, error) in

			if let data = data, !data.isEmpty, let response = response, response.statusIsOK, error == nil {

				let parserData = ParserData(url: homePageURL, data: data)
				let metadata = RSHTMLMetadataParser.htmlMetadata(with: parserData)
				self.pullIconURL(from: metadata, homePageURL: homePageURL)
				return
			}

			if let error = error {
				appDelegate.logMessage("Error finding icon url at \(homePageURL): \(error)", type: .warning)
			}
		}
	}

	func pullIconURL(from metadata: RSHTMLMetadata, homePageURL: String) {

		if let openGraphImageURL = largestOpenGraphImageURL(from: metadata) {
			cacheIconURL(for: homePageURL, openGraphImageURL)
			return
		}

		if let twitterImageURL = metadata.twitterProperties.imageURL {
			cacheIconURL(for: homePageURL, twitterImageURL)
		}
	}

	func largestOpenGraphImageURL(from metadata: RSHTMLMetadata) -> String? {

		guard let openGraphImages = metadata.openGraphProperties?.images else {
			return nil
		}

		var bestImage: RSHTMLOpenGraphImage? = nil

		for image in openGraphImages {
			if bestImage == nil {
				bestImage = image
				continue
			}
			if image.height > bestImage!.height && image.width > bestImage!.width {
				bestImage = image
			}
		}

		return bestImage?.secureURL ?? bestImage?.url
	}
}
