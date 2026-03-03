/*
  RoomPlanCatalog.swift

  Adapted from Apple's "Providing custom models for captured rooms and structure exports" sample.
  See: https://developer.apple.com/documentation/roomplan/providing-custom-models-for-captured-rooms-and-structure-exports

  This file loads a RoomPlanCatalog.bundle (containing a catalog.plist index
  and .usdc 3D model files) and produces a CapturedRoom.ModelProvider that
  maps detected furniture categories/attributes to those 3D models.
*/

import Foundation
import RoomPlan
import os

/// A structure that manages a catalog index for loading 3D furniture models.
@available(iOS 17.0, *)
struct RoomPlanCatalog: Codable {

    /// The name of the catalog index file inside the bundle.
    static let catalogIndexFilename = "catalog.plist"

    /// An array of categories and attributes that the catalog supports.
    let categoryAttributes: [RoomPlanCatalogCategoryAttribute]

    /// Loads a catalog bundle at the given URL and returns a populated ModelProvider.
    static func load(at url: URL) throws -> CapturedRoom.ModelProvider {
        let catalogPListURL = url.appending(path: RoomPlanCatalog.catalogIndexFilename)
        let data = try Data(contentsOf: catalogPListURL)
        let propertyListDecoder = PropertyListDecoder()
        let catalog = try propertyListDecoder.decode(RoomPlanCatalog.self, from: data)

        var modelProvider = CapturedRoom.ModelProvider()

        for categoryAttribute in catalog.categoryAttributes {
            guard let modelFilename = categoryAttribute.modelFilename else { continue }
            let folderRelativePath = categoryAttribute.folderRelativePath
            let modelURL = url.appending(path: folderRelativePath).appending(path: modelFilename)

            // Verify the file exists before trying to register it
            guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
                Logger().warning("[RoomPlanCatalog] Model file missing: \(modelURL.lastPathComponent)")
                continue
            }

            if categoryAttribute.attributes.isEmpty {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.category)
                } catch {
                    Logger().warning("[RoomPlanCatalog] Can't add \(modelURL.lastPathComponent) for category: \(error.localizedDescription)")
                }
            } else {
                do {
                    try modelProvider.setModelFileURL(modelURL, for: categoryAttribute.attributes)
                } catch {
                    Logger().warning("[RoomPlanCatalog] Can't add \(modelURL.lastPathComponent) for attributes: \(error.localizedDescription)")
                }
            }
        }

        return modelProvider
    }
}

/// A structure that holds a category, its attributes, and the path to the 3D model file.
@available(iOS 17.0, *)
struct RoomPlanCatalogCategoryAttribute: Codable {
    enum CodingKeys: String, CodingKey {
        case folderRelativePath
        case category
        case attributes
        case modelFilename
    }

    /// A relative path of the folder that contains a 3D model.
    let folderRelativePath: String

    /// An object category for a 3D model.
    let category: CapturedRoom.Object.Category

    /// An array of object attributes.
    let attributes: [any CapturedRoomAttribute]

    /// A filename for the 3D model.
    private(set) var modelFilename: String? = nil

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderRelativePath = try container.decode(String.self, forKey: .folderRelativePath)
        category = try container.decode(CapturedRoom.Object.Category.self, forKey: .category)
        let attributesCodableRepresentation = try container.decode(
            CapturedRoom.AttributesCodableRepresentation.self, forKey: .attributes)
        attributes = attributesCodableRepresentation.attributes
        modelFilename = try? container.decode(String.self, forKey: .modelFilename)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.folderRelativePath, forKey: .folderRelativePath)
        try container.encode(self.category, forKey: .category)
        let attributesCodableRepresentation = CapturedRoom.AttributesCodableRepresentation(
            attributes: attributes)
        try container.encode(attributesCodableRepresentation, forKey: .attributes)
        try container.encode(self.modelFilename, forKey: .modelFilename)
    }
}

// MARK: - Convenience extension for loading from the app bundle

@available(iOS 17.0, *)
extension CapturedRoom.ModelProvider {

    /// An error subclass for model catalogs.
    enum CatalogError: LocalizedError {
        case cannotFindCatalog

        var errorDescription: String? {
            switch self {
            case .cannotFindCatalog:
                return "Cannot find RoomPlanCatalog.bundle in the app bundle."
            }
        }
    }

    /// Loads the RoomPlanCatalog.bundle from the app's main bundle.
    /// Returns a ModelProvider populated with all 3D model mappings from the catalog.
    static func loadFromCatalog() throws -> CapturedRoom.ModelProvider {
        guard let catalogURL = Bundle.main.url(forResource: "RoomPlanCatalog", withExtension: "bundle") else {
            throw CatalogError.cannotFindCatalog
        }
        return try RoomPlanCatalog.load(at: catalogURL)
    }
}
