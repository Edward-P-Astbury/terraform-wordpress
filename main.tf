terraform {
  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "resgroup-network" {
  name     = "rg-network"
  location = "australiaeast"
}

resource "azurerm_resource_group" "resgroup-product" {
  name     = "rg-product"
  location = "australiaeast"
}

resource "azurerm_network_security_group" "nsg-database" {
  name                = "nsg-database"
  location            = azurerm_resource_group.resgroup-network.location
  resource_group_name = azurerm_resource_group.resgroup-network.name

  // --- Rules for Linux VM (database) ---
  security_rule {
    name                       = "SSH"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MySQL"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.0.0/8" // Internal network
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg-web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.resgroup-network.location
  resource_group_name = azurerm_resource_group.resgroup-network.name

  // --- Rules for Linux VM (webapp) ---
  security_rule {
    name                       = "SSH"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MySQL"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.0.0/8" // Internal network
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "vn-product" {
  name                = "vn-product"
  location            = "australiaeast"
  resource_group_name = azurerm_resource_group.resgroup-network.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sn-web" {
  name                 = "sn-web"
  resource_group_name  = azurerm_resource_group.resgroup-network.name
  virtual_network_name = azurerm_virtual_network.vn-product.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "sn-database" {
  name                 = "sn-database"
  resource_group_name  = azurerm_resource_group.resgroup-network.name
  virtual_network_name = azurerm_virtual_network.vn-product.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Connect the security group to the network interface
resource "azurerm_subnet_network_security_group_association" "nsg-assoc-web" {
  subnet_id                 = azurerm_subnet.sn-web.id
  network_security_group_id = azurerm_network_security_group.nsg-web.id
}

# Connect the security group to the network interface
resource "azurerm_subnet_network_security_group_association" "nsg-assoc-database" {
  subnet_id                 = azurerm_subnet.sn-database.id
  network_security_group_id = azurerm_network_security_group.nsg-database.id
}

# Public IP for the LB
resource "azurerm_public_ip" "public-ip" {
  name                = "public-ip"
  resource_group_name = azurerm_resource_group.resgroup-network.name
  location            = azurerm_resource_group.resgroup-network.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "network-lb" {
  name                = "network-lb"
  location            = azurerm_resource_group.resgroup-network.location
  resource_group_name = azurerm_resource_group.resgroup-network.name
  sku                 = "Standard" // Changed to Standard, need to support AZ

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.public-ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "lb-backend" {
  loadbalancer_id = azurerm_lb.network-lb.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_rule" "lb-rule-tcp" {
  loadbalancer_id                = azurerm_lb.network-lb.id
  resource_group_name            = azurerm_resource_group.resgroup-network.name
  name                           = "LBRuleTCP"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.lb-probe-tcp.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb-backend.id]
}

resource "azurerm_lb_rule" "lb-rule-ssh" {
  loadbalancer_id                = azurerm_lb.network-lb.id
  resource_group_name            = azurerm_resource_group.resgroup-network.name
  name                           = "LBRuleSSH"
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.lb-probe-ssh.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb-backend.id]
}

resource "azurerm_lb_rule" "lb-rule-https" {
  loadbalancer_id                = azurerm_lb.network-lb.id
  resource_group_name            = azurerm_resource_group.resgroup-network.name
  name                           = "LBRuleHTTPS"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.lb-probe-https.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb-backend.id]
}

// --- Create association between backend address pool and the NIC ---
resource "azurerm_network_interface_backend_address_pool_association" "lb-backend-assoc" {
  network_interface_id    = azurerm_network_interface.web-nic.id
  ip_configuration_name   = "internal-web"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb-backend.id
}

resource "azurerm_network_interface_backend_address_pool_association" "lb-backend-assoc-ha" {
  network_interface_id    = azurerm_network_interface.web-nic-ha.id
  ip_configuration_name   = "internal-web"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb-backend.id
}

resource "azurerm_lb_probe" "lb-probe-ssh" {
  resource_group_name = azurerm_resource_group.resgroup-network.name
  loadbalancer_id     = azurerm_lb.network-lb.id
  name                = "ssh-running-probe"
  port                = 22
}

resource "azurerm_lb_probe" "lb-probe-tcp" {
  resource_group_name = azurerm_resource_group.resgroup-network.name
  loadbalancer_id     = azurerm_lb.network-lb.id
  name                = "tcp-running-probe"
  port                = 80
}

resource "azurerm_lb_probe" "lb-probe-https" {
  resource_group_name = azurerm_resource_group.resgroup-network.name
  loadbalancer_id     = azurerm_lb.network-lb.id
  name                = "https-running-probe"
  port                = 443
}

resource "azurerm_network_interface" "web-nic" {
  name                = "web-nic"
  location            = azurerm_resource_group.resgroup-product.location
  resource_group_name = azurerm_resource_group.resgroup-product.name

  ip_configuration {
    name                          = "internal-web"
    subnet_id                     = azurerm_subnet.sn-web.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "web-nic-ha" {
  name                = "web-nic-ha"
  location            = azurerm_resource_group.resgroup-product.location
  resource_group_name = azurerm_resource_group.resgroup-product.name

  ip_configuration {
    name                          = "internal-web"
    subnet_id                     = azurerm_subnet.sn-web.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "database-nic" {
  name                = "database-nic"
  location            = azurerm_resource_group.resgroup-product.location
  resource_group_name = azurerm_resource_group.resgroup-product.name

  ip_configuration {
    name                          = "internal-web"
    subnet_id                     = azurerm_subnet.sn-database.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "webapp-vm" {
  name                            = "webapp-vm"
  location                        = azurerm_resource_group.resgroup-product.location
  resource_group_name             = azurerm_resource_group.resgroup-product.name
  network_interface_ids           = [azurerm_network_interface.web-nic.id]
  size                            = "Standard_B2s"
  admin_username                  = "adminuser"
  admin_password                  = "$wordpress123"
  disable_password_authentication = false
  // --- AZ for stage 2 ---
  zone = "1"

  os_disk {
    name                 = "webapp-vm-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
    version   = "20.04.202204040"
  }
}

resource "azurerm_linux_virtual_machine" "webapp-vm-ha" {
  name                            = "webapp-vm-ha"
  location                        = azurerm_resource_group.resgroup-product.location
  resource_group_name             = azurerm_resource_group.resgroup-product.name
  network_interface_ids           = [azurerm_network_interface.web-nic-ha.id]
  size                            = "Standard_B2s"
  admin_username                  = "adminuser"
  admin_password                  = "$wordpress123"
  disable_password_authentication = false
  // --- AZ for stage 2 ---
  zone = "2"

  os_disk {
    name                 = "webapp-vm-ha-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
    version   = "20.04.202204040"
  }
}

resource "azurerm_linux_virtual_machine" "database-vm" {
  name                            = "database-vm"
  location                        = azurerm_resource_group.resgroup-product.location
  resource_group_name             = azurerm_resource_group.resgroup-product.name
  network_interface_ids           = [azurerm_network_interface.database-nic.id]
  size                            = "Standard_B2s"
  admin_username                  = "adminuser"
  admin_password                  = "$wordpress123"
  disable_password_authentication = false
  // --- AZ for stage 2 ---
  zone = "1"

  os_disk {
    name                 = "database-vm-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
    version   = "20.04.202204040"
  }
}
