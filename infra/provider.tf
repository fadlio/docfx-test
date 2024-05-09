provider "google" {
  credentials = file("svc.json")
  project     =  var.project_id
  region      = "us-central1" # e.g., "us-central1"
}

provider "random" {
  
}