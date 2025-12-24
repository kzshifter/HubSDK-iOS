import Foundation

enum LocalizationError: Error {
    case invalidJSON
    case decodingFailed
}

final class JSONLocalizer {
    private let languageCode: String
    
    init(languageCode: String? = nil) {
        self.languageCode = languageCode ?? Locale.current.languageCode ?? "en"
    }
    
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalizationError.invalidJSON
        }
        
        let localizedJson = localizeJSON(json)
        let localizedData = try JSONSerialization.data(withJSONObject: localizedJson)
        
        return try JSONDecoder().decode(type, from: localizedData)
    }
    
    private func localizeJSON(_ json: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        for (key, value) in json {
            result[key] = localizeValue(value)
        }
        
        return result
    }
    
    private func localizeValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            if isLocalizationDict(dict) {
                getLocalizedValue(from: dict) ?? value
            } else {
                localizeJSON(dict)
            }
        } else if let array = value as? [Any] {
            array.map { localizeValue($0) }
        } else {
            value
        }
    }
    
    private func isLocalizationDict(_ dict: [String: Any]) -> Bool {
        guard !dict.isEmpty else { return false }
        
        return dict.keys.allSatisfy { key in
            key.count >= 2 && 
            key.count <= 5 && 
            key.range(of: "^[a-z]{2}(-[A-Z]{2})?$", options: .regularExpression) != nil
        }
    }
    
    private func getLocalizedValue(from data: [String: Any]) -> Any? {
        if let value = data[languageCode] {
            return value
        }
        
        if let value = data["en"] {
            return value
        }
        
        if let value = data.first(where: { $0.key.hasPrefix(languageCode + "-") })?.value {
            return value
        }
        
        return data.values.first
    }
}

extension JSONLocalizer {
    func decode<T: Decodable>(from data: Data) throws -> T {
        try decode(T.self, from: data)
    }
}
