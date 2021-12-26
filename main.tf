################################################################################
# VPC
################################################################################

resource "aws_vpc"  "vpc_main" {

  cidr_block           =  var.cidr
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(
  {
    "Name" = format("%s", var.name)
  },
  var.tags,
  var.vpc_tags,
  )
}

################################################################################
# Public subnet
################################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnets) > 0 ? length(var.public_subnets) : 0

  vpc_id                          = aws_vpc.vpc_main.id
  cidr_block                      = element(concat(var.public_subnets, [""]), count.index)
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  map_public_ip_on_launch         = var.map_public_ip_on_launch

  tags = merge(
  {
    "Name" = format(
    "%s-${var.public_subnet_suffix}-%s",
    var.name,
    element(var.azs, count.index),
    )
  },
  var.tags,
  var.public_subnet_tags,
  )
}

################################################################################
# Private subnet
################################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  vpc_id                          = aws_vpc.vpc_main.id
  cidr_block                      = var.private_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null

  tags = merge(
  {
    "Name" = format(
    "%s-${var.private_subnet_suffix}-%s",
    var.name,
    element(var.azs, count.index),
    )
  },
  var.tags,
  var.private_subnet_tags,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "vpc_igw" {
  vpc_id = aws_vpc.vpc_main.id

  tags = merge(
  {
    "Name" = format("%s", var.name)
  },
  var.tags,
  var.igw_tags,
  )
}

################################################################################
# Publiс routes
################################################################################

resource "aws_route_table" "public" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.vpc_main.id

  tags = merge(
  {
    "Name" = format("%s-${var.public_subnet_suffix}", var.name)
  },
  var.tags,
  var.public_route_table_tags,
  )
}

resource "aws_route" "public_internet_gateway" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc_igw.id

  timeouts {
    create = "5m"
  }
}

################################################################################
# Private routes
################################################################################

resource "aws_route_table" "private" {
  count =  length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  vpc_id = aws_vpc.vpc_main.id

  tags = merge(
  {
    "Name" =  format("%s-${var.private_subnet_suffix}-%s", var.name, element(var.azs, count.index), )
  },
  var.tags,
  var.private_route_table_tags,
  )
}

################################################################################
# Route table association
################################################################################

# Publiс ######################################################################
resource "aws_route_table_association" "public" {
  count = length(var.public_subnets) > 0 ? length(var.public_subnets) : 0

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public[0].id
}

# Private  ####################################################################
resource "aws_route_table_association" "private" {
  count = length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  subnet_id = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index, )
}

################################################################################
# NAT Gateway
################################################################################

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(var.azs) : 0

  vpc = true

  tags = merge(
  {
    "Name" = format(
    "%s-%s",
    var.name, element(var.azs, count.index), )
  },
  var.tags,
  var.nat_eip_tags,
  )
}

resource "aws_nat_gateway" "gw_nat" {
  count = var.enable_nat_gateway ? length(var.azs) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(
  {
    "Name" = format(
    "%s-%s",
    var.name,
    element(var.azs, count.index), )
  },
  var.tags,
  var.nat_gateway_tags,
  )

  depends_on = [aws_internet_gateway.vpc_igw]
}

resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? length(var.azs) : 0

  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.gw_nat.*.id, count.index)

  timeouts {
    create = "5m"
  }
}

################################################################################
# DHCP Options Set
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count =  var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers

  tags = merge(
  {
    "Name" = format("%s", var.name)
  },
  var.tags,
  var.dhcp_options_tags,
  )
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  vpc_id          = aws_vpc.vpc_main.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}


