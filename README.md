# Princeton EAD Exporter

Customizes ArchiveSpace EAD output to include location codes for containers.

Install instructions: 
1. clone the princeton_ead_exporter repository into the plugins directory 
2. enable the plugin in ArchivesSpace:
   a. create .config if it doesn't exist  
   b. copy config/config-defaults.rb into config and rename the file config.rb  
   c. add the exporter to config.rb: AppConfig[:plugins] = ['princeton_ead_exporter']  
3. Restart ArchivesSpace
