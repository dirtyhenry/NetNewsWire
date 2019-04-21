//
//  MasterTimelineViewController.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 4/8/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account
import Articles

class MasterTimelineViewController: UITableViewController, UndoableCommandRunner {

	private var rowHeightWithFeedName: CGFloat = 0.0
	private var rowHeightWithoutFeedName: CGFloat = 0.0
	
	private var currentRowHeight: CGFloat {
		return nmc.showFeedNames ? rowHeightWithFeedName : rowHeightWithoutFeedName
	}

	var nmc: NavigationModelController!
	var undoableCommands = [UndoableCommand]()
	
	var detailViewController: DetailViewController? {
		if let split = splitViewController {
			let controllers = split.viewControllers
			return (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
		}
		return nil
	}
		
	override var canBecomeFirstResponder: Bool {
		return true
	}
	
	override func viewDidLoad() {
		
		super.viewDidLoad()
		updateRowHeights()
		
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(feedIconDidBecomeAvailable(_:)), name: .FeedIconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(avatarDidBecomeAvailable(_:)), name: .AvatarDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable(_:)), name: .ImageDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(imageDidBecomeAvailable(_:)), name: .FaviconDidBecomeAvailable, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(progressDidChange(_:)), name: .AccountRefreshProgressDidChange, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(articlesReinitialized(_:)), name: .ArticlesReinitialized, object: nmc)
		NotificationCenter.default.addObserver(self, selector: #selector(showFeedNamesDidChange(_:)), name: .ShowFeedNamesDidChange, object: nmc)
		NotificationCenter.default.addObserver(self, selector: #selector(articleDataDidChange(_:)), name: .ArticleDataDidChange, object: nmc)
		NotificationCenter.default.addObserver(self, selector: #selector(articlesDidChange(_:)), name: .ArticlesDidChange, object: nmc)

		refreshControl = UIRefreshControl()
		refreshControl!.addTarget(self, action: #selector(refreshAccounts(_:)), for: .valueChanged)
		
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		becomeFirstResponder()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		resignFirstResponder()
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "showDetail" {
			if let indexPath = tableView.indexPathForSelectedRow {
				let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
				let article = nmc.articles[indexPath.row]
				controller.article = article
				controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
				controller.navigationItem.leftItemsSupplementBackButton = true
				splitViewController?.toggleMasterView()
			}
		}
	}
	
	// MARK Actions

	@IBAction func markAllAsRead(_ sender: Any) {
		
		let title = NSLocalizedString("Mark All Read", comment: "Mark All Read")
		let message = NSLocalizedString("Mark all articles in this timeline as read?", comment: "Mark all articles")
		let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel")
		let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel)
		alertController.addAction(cancelAction)
		
		let markTitle = NSLocalizedString("Mark All Read", comment: "Mark All Read")
		let markAction = UIAlertAction(title: markTitle, style: .default) { [weak self] (action) in

			guard let articles = self?.nmc.articles,
				let undoManager = self?.undoManager,
				let markReadCommand = MarkStatusCommand(initialArticles: articles, markingRead: true, undoManager: undoManager) else {
				return
			}
			self?.runCommand(markReadCommand)
			
		}
		alertController.addAction(markAction)
		
		present(alertController, animated: true)
		
	}
	
	// MARK: - Table view

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return nmc.articles.count
    }

	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		
		let article = nmc.articles[indexPath.row]
		
		// Set up the star action
		let starTitle = article.status.starred ?
			NSLocalizedString("Unstar", comment: "Unstar") :
			NSLocalizedString("Star", comment: "Star")
		
		let starAction = UIContextualAction(style: .normal, title: starTitle) { [weak self] (action, view, completionHandler) in
			guard let undoManager = self?.undoManager,
				let markReadCommand = MarkStatusCommand(initialArticles: [article], markingStarred: !article.status.starred, undoManager: undoManager) else {
					return
			}
			self?.runCommand(markReadCommand)
			completionHandler(true)
		}
		
		starAction.image = AppAssets.starClosedImage
		starAction.backgroundColor = AppAssets.starColor
		
		// Set up the read action
		let readTitle = article.status.read ?
			NSLocalizedString("Unread", comment: "Unread") :
			NSLocalizedString("Read", comment: "Read")
		
		let readAction = UIContextualAction(style: .normal, title: readTitle) { [weak self] (action, view, completionHandler) in
			guard let undoManager = self?.undoManager,
				let markReadCommand = MarkStatusCommand(initialArticles: [article], markingRead: !article.status.read, undoManager: undoManager) else {
					return
			}
			self?.runCommand(markReadCommand)
			completionHandler(true)
		}
		
		readAction.image = AppAssets.circleClosedImage
		readAction.backgroundColor = AppAssets.timelineUnreadCircleColor
		
		let configuration = UISwipeActionsConfiguration(actions: [starAction, readAction])
		return configuration
		
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! MasterTimelineTableViewCell
		let article = nmc.articles[indexPath.row]

		configureTimelineCell(cell, article: article)
		
		return cell
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let article = nmc.articles[indexPath.row]
		if !article.status.read {
			markArticles(Set([article]), statusKey: .read, flag: true)
		}
	}
	
	// MARK: Notifications

	@objc dynamic func progressDidChange(_ notification: Notification) {
		if AccountManager.shared.combinedRefreshProgress.isComplete {
			refreshControl?.endRefreshing()
		} else {
			refreshControl?.beginRefreshing()
		}
	}

	@objc func statusesDidChange(_ note: Notification) {
		
		guard let articles = note.userInfo?[Account.UserInfoKey.articles] as? Set<Article> else {
			return
		}
		reloadVisibleCells(for: articles)
	}

	@objc func feedIconDidBecomeAvailable(_ note: Notification) {
		
		guard let feed = note.userInfo?[UserInfoKey.feed] as? Feed else {
			return
		}
		
		performBlockAndRestoreSelection {
			tableView.indexPathsForVisibleRows?.forEach { indexPath in
				
				guard let article = nmc.articles.articleAtRow(indexPath.row) else {
					return
				}
				
				if feed == article.feed {
					tableView.reloadRows(at: [indexPath], with: .none)
					return
				}
				
			}
		}

	}

	@objc func avatarDidBecomeAvailable(_ note: Notification) {
		
		guard nmc.showAvatars, let avatarURL = note.userInfo?[UserInfoKey.url] as? String else {
			return
		}
		
		performBlockAndRestoreSelection {
			tableView.indexPathsForVisibleRows?.forEach { indexPath in
				
				guard let article = nmc.articles.articleAtRow(indexPath.row), let authors = article.authors, !authors.isEmpty else {
					return
				}
				
				for author in authors {
					if author.avatarURL == avatarURL {
						tableView.reloadRows(at: [indexPath], with: .none)
					}
				}

			}
		}
		
	}

	@objc func imageDidBecomeAvailable(_ note: Notification) {
		if nmc.showAvatars {
			queueReloadVisableCells()
		}
	}

	@objc func articlesReinitialized(_ note: Notification) {
		if nmc.articles.count > 0 {
			tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
		}
	}
	
	@objc func showFeedNamesDidChange(_ note: Notification) {
		updateTableViewRowHeight()
	}
	
	@objc func articleDataDidChange(_ note: Notification) {
		reloadAllVisibleCells()
	}
	
	@objc func articlesDidChange(_ note: Notification) {
		tableView.reloadData()
	}
	
	// MARK: Reloading
	
	@objc func reloadAllVisibleCells() {
		tableView.beginUpdates()
		performBlockAndRestoreSelection {
			tableView.reloadRows(at: tableView.indexPathsForVisibleRows!, with: .none)
		}
		tableView.endUpdates()
	}
	
	private func reloadVisibleCells(for articles: [Article]) {
		reloadVisibleCells(for: Set(articles.articleIDs()))
	}
	
	private func reloadVisibleCells(for articles: Set<Article>) {
		reloadVisibleCells(for: articles.articleIDs())
	}
	
	private func reloadVisibleCells(for articleIDs: Set<String>) {
		if articleIDs.isEmpty {
			return
		}
		let indexes = nmc.indexesForArticleIDs(articleIDs)
		reloadVisibleCells(for: indexes)
	}
	
	private func reloadVisibleCells(for indexes: IndexSet) {
		performBlockAndRestoreSelection {
			tableView.indexPathsForVisibleRows?.forEach { indexPath in
				if indexes.contains(indexPath.row) {
					tableView.reloadRows(at: [indexPath], with: .none)
				}
			}
		}
	}
	
	// MARK: Cell Configuring

	private func calculateRowHeight(showingFeedNames: Bool) -> CGFloat {
		
		let longTitle = "But I must explain to you how all this mistaken idea of denouncing pleasure and praising pain was born and I will give you a complete account of the system, and expound the actual teachings of the great explorer of the truth, the master-builder of human happiness. No one rejects, dislikes, or avoids pleasure itself, because it is pleasure, but because those who do not know how to pursue pleasure rationally encounter consequences that are extremely painful. Nor again is there anyone who loves or pursues or desires to obtain pain of itself, because it is pain, but because occasionally circumstances occur in which toil and pain can procure him some great pleasure. To take a trivial example, which of us ever undertakes laborious physical exercise, except to obtain some advantage from it? But who has any right to find fault with a man who chooses to enjoy a pleasure that has no annoying consequences, or one who avoids a pain that produces no resultant pleasure?"
		
		let prototypeID = "prototype"
		let status = ArticleStatus(articleID: prototypeID, read: false, starred: false, userDeleted: false, dateArrived: Date())
		let prototypeArticle = Article(accountID: prototypeID, articleID: prototypeID, feedID: prototypeID, uniqueID: prototypeID, title: longTitle, contentHTML: nil, contentText: nil, url: nil, externalURL: nil, summary: nil, imageURL: nil, bannerImageURL: nil, datePublished: nil, dateModified: nil, authors: nil, attachments: nil, status: status)
		
		let prototypeCellData = MasterTimelineCellData(article: prototypeArticle, showFeedName: showingFeedNames, feedName: "Prototype Feed Name", avatar: nil, showAvatar: false, featuredImage: nil)
		let height = MasterTimelineCellLayout.height(for: 100, cellData: prototypeCellData)
		return height
		
	}
	
	private func updateRowHeights() {
		rowHeightWithFeedName = calculateRowHeight(showingFeedNames: true)
		rowHeightWithoutFeedName = calculateRowHeight(showingFeedNames: false)
		updateTableViewRowHeight()
	}
	
}

// MARK: Private

private extension MasterTimelineViewController {
	
	@objc private func refreshAccounts(_ sender: Any) {
		AccountManager.shared.refreshAll()
	}
	
	func configureTimelineCell(_ cell: MasterTimelineTableViewCell, article: Article) {
		
		var avatar = avatarFor(article)
		if avatar == nil, let feed = article.feed {
			avatar = appDelegate.faviconDownloader.favicon(for: feed)
		}
		let featuredImage = featuredImageFor(article)
		
		cell.cellData = MasterTimelineCellData(article: article, showFeedName: nmc.showFeedNames, feedName: article.feed?.nameForDisplay, avatar: avatar, showAvatar: nmc.showAvatars, featuredImage: featuredImage)
		
	}
	
	func avatarFor(_ article: Article) -> UIImage? {
		
		if !nmc.showAvatars {
			return nil
		}
		
		if let authors = article.authors {
			for author in authors {
				if let image = avatarForAuthor(author) {
					return image
				}
			}
		}
		
		guard let feed = article.feed else {
			return nil
		}
		
		return appDelegate.feedIconDownloader.icon(for: feed)
		
	}
	
	func avatarForAuthor(_ author: Author) -> UIImage? {
		return appDelegate.authorAvatarDownloader.image(for: author)
	}
	
	func featuredImageFor(_ article: Article) -> UIImage? {
		if let url = article.imageURL, let data = appDelegate.imageDownloader.image(for: url) {
			return RSImage(data: data)
		}
		return nil
	}

	func queueReloadVisableCells() {
		CoalescingQueue.standard.add(self, #selector(reloadAllVisibleCells))
	}

	func updateTableViewRowHeight() {
		tableView.rowHeight = currentRowHeight
		tableView.estimatedRowHeight = currentRowHeight
	}

	func performBlockAndRestoreSelection(_ block: (() -> Void)) {
		let indexPaths = tableView.indexPathsForSelectedRows
		block()
		indexPaths?.forEach { [weak self] indexPath in
			self?.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
		}
	}
	
}
