output "transit_gateway" {
  description = "The created Transit GW as an object with all of it's attributes."
  value       = module.firenet.transit_gateway
}
 
output "transit_vpc" {
  description = "The created Transit VPC as an object with all of it's attributes."
  value       = module.firenet.vpc
}
  
output "firewall" {
  description = "Firewall and all of it's attributes"
  value       = module.fw.vm
}
