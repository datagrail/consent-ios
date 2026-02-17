Pod::Spec.new do |s|
  s.name         = 'DataGrailConsent'
  s.version      = '1.0.0'
  s.summary      = 'Native iOS SDK for consent banner display and privacy preference management.'
  s.description  = <<-DESC
    DataGrail Consent SDK provides a native iOS consent banner implementation
    for managing user privacy preferences. It supports multi-layer consent flows,
    offline queuing with retry, category-level consent management, and real-time
    backend synchronization.
  DESC

  s.homepage     = 'https://github.com/datagrail/consent-banner'
  s.license      = { type: 'Apache-2.0', file: 'LICENSE' }
  s.author       = { 'DataGrail' => 'support@datagrail.com' }

  s.source       = {
    git: 'https://github.com/datagrail/consent-banner.git',
    tag: s.version.to_s
  }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/DataGrailConsent/**/*.swift'

  s.frameworks = 'Foundation', 'UIKit'
end
